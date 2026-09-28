using System.Text;
using System.Text.Json.Serialization;
using BizFlow.Api.Data;
using BizFlow.Api.Dtos;
using BizFlow.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// ----------------------------------------------------------------- options
var jwt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
if (string.IsNullOrWhiteSpace(jwt.Key) || jwt.Key.Length < 32)
    throw new InvalidOperationException("Jwt:Key must be set to at least 32 characters in appsettings.json.");
builder.Services.AddSingleton(jwt);

var whatsApp = builder.Configuration.GetSection("WhatsApp").Get<WhatsAppOptions>() ?? new WhatsAppOptions();
builder.Services.AddSingleton(whatsApp);

var storage = builder.Configuration.GetSection("Storage").Get<StorageOptions>() ?? new StorageOptions();
builder.Services.AddSingleton(storage);

// -------------------------------------------------------------- services
// No EnableRetryOnFailure: the retrying execution strategy refuses the explicit
// transactions that billing and credit claims rely on. Against a local SQL Server
// there is nothing transient to retry anyway.
builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Default")));

builder.Services.AddHttpContextAccessor();
builder.Services.AddHttpClient();
builder.Services.AddScoped<ICurrentUser, CurrentUser>();
builder.Services.AddScoped<ITokenService, TokenService>();
builder.Services.AddScoped<IBookkeepingService, BookkeepingService>();
builder.Services.AddScoped<IWhatsAppService, WhatsAppService>();
builder.Services.AddScoped<ICustomerInsightService, CustomerInsightService>();
builder.Services.AddSingleton<IFileStorageService, FileStorageService>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer              = jwt.Issuer,
            ValidAudience            = jwt.Audience,
            IssuerSigningKey         = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.Key)),
            ClockSkew                = TimeSpan.FromMinutes(1)
        };
    });
builder.Services.AddAuthorization();

builder.Services.AddScoped<ActiveWorkerFilter>();
builder.Services.AddControllers(o => o.Filters.AddService<ActiveWorkerFilter>())
    .AddJsonOptions(o =>
    {
        o.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        o.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
    });

// Validation failures come back in the same envelope as everything else (FR-045).
builder.Services.Configure<ApiBehaviorOptions>(o =>
{
    o.InvalidModelStateResponseFactory = ctx =>
    {
        var errors = ctx.ModelState
            .Where(kv => kv.Value?.Errors.Count > 0)
            .ToDictionary(kv => kv.Key, kv => kv.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
        return new BadRequestObjectResult(ApiResponse<object>.Fail("Please check the details you entered.", errors));
    };
});

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "BizBill API", Version = "v1" });
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "Paste the JWT here (no 'Bearer ' prefix needed).",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT"
    });
    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

// The mobile app talks to this API from a device/emulator, so keep CORS open in dev.
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

// -------------------------------------------------------------- pipeline
app.UseExceptionHandler(a => a.Run(async ctx =>
{
    var ex = ctx.Features.Get<IExceptionHandlerFeature>()?.Error;
    app.Logger.LogError(ex, "Unhandled error on {Path}", ctx.Request.Path);
    ctx.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await ctx.Response.WriteAsJsonAsync(
        ApiResponse<object>.Fail("Something went wrong. Please try again."));
}));

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "BizBill API v1");
    c.RoutePrefix = "swagger";
});

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapGet("/", () => Results.Ok(new
{
    name = "BizBill API",
    status = "running",
    swagger = "/swagger",
    utc = DateTime.UtcNow
}));

app.MapGet("/health", async (AppDbContext db) =>
{
    var canConnect = await db.Database.CanConnectAsync();
    return canConnect
        ? Results.Ok(new { database = "connected", status = "healthy" })
        : Results.Problem("Cannot reach the database.");
});

// ------------------------------------------------- database check + seed
using (var scope = app.Services.CreateScope())
{
    var db  = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var log = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    try
    {
        if (!await db.Database.CanConnectAsync())
            log.LogError("Cannot connect to SQL Server. Run API/Database/run-database-setup.ps1 first.");
        else
        {
            // Tables and columns added after the first release (UPI, barcodes,
            // workers / HRMS, card payments). Safe to run on every start.
            await SchemaUpgrade.ApplyAsync(db, log);

            await DataSeeder.SeedAsync(db, log);
            try { await DataSeeder.SeedWorkersAsync(db, log); }
            catch (Exception ex) { log.LogWarning(ex, "Demo workers were not added."); }
        }
    }
    catch (Exception ex)
    {
        log.LogError(ex, "Startup database check failed.");
    }
}

app.Run();
