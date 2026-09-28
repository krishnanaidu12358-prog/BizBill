namespace BizFlow.Api.Services;

public class StorageOptions
{
    /// <summary>Folder for uploaded payment screenshots. Relative paths resolve under the content root.</summary>
    public string UploadsPath { get; set; } = "App_Data/uploads";
    public int MaxFileSizeBytes { get; set; } = 5 * 1024 * 1024;
}

public class StoredFile
{
    public string RelativePath { get; set; } = "";
    public string FileName { get; set; } = "";
    public string ContentType { get; set; } = "";
    public int Size { get; set; }
}

public interface IFileStorageService
{
    /// <summary>Validates and saves an uploaded image. Throws InvalidOperationException on a bad file.</summary>
    Task<StoredFile> SaveImageAsync(IFormFile file, string folder, CancellationToken ct = default,
                                    string what = "screenshot");

    /// <summary>Absolute path for a stored relative path, or null when the file is gone.</summary>
    string? ResolvePath(string? relativePath);

    void Delete(string? relativePath);
}

public class FileStorageService : IFileStorageService
{
    private static readonly Dictionary<string, string> AllowedTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["image/jpeg"] = ".jpg",
        ["image/jpg"]  = ".jpg",
        ["image/png"]  = ".png",
        ["image/webp"] = ".webp",
        ["image/heic"] = ".heic"
    };

    private readonly StorageOptions _opt;
    private readonly string _root;

    public FileStorageService(StorageOptions opt, IWebHostEnvironment env)
    {
        _opt = opt;
        _root = Path.IsPathRooted(opt.UploadsPath)
            ? opt.UploadsPath
            : Path.Combine(env.ContentRootPath, opt.UploadsPath);
        Directory.CreateDirectory(_root);
    }

    public async Task<StoredFile> SaveImageAsync(IFormFile file, string folder, CancellationToken ct = default,
                                                 string what = "screenshot")
    {
        if (file.Length == 0)
            throw new InvalidOperationException($"The {what} is empty.");

        if (file.Length > _opt.MaxFileSizeBytes)
            throw new InvalidOperationException(
                $"The {what} is too large. Keep it under {_opt.MaxFileSizeBytes / (1024 * 1024)} MB.");

        if (!AllowedTypes.TryGetValue(file.ContentType ?? "", out var extension))
            throw new InvalidOperationException(what == "screenshot"
                ? "Upload a JPG, PNG or WEBP image of the payment."
                : $"Upload the {what} as a JPG or PNG image.");

        var safeFolder = Path.Combine(_root, SanitiseFolder(folder));
        Directory.CreateDirectory(safeFolder);

        // Never trust the client's filename - generate our own.
        var name = $"{DateTime.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}{extension}";
        var fullPath = Path.Combine(safeFolder, name);

        await using (var stream = File.Create(fullPath))
        {
            await file.CopyToAsync(stream, ct);
        }

        return new StoredFile
        {
            RelativePath = Path.Combine(SanitiseFolder(folder), name).Replace('\\', '/'),
            FileName     = Path.GetFileName(file.FileName) ?? name,
            ContentType  = file.ContentType!,
            Size         = (int)file.Length
        };
    }

    public string? ResolvePath(string? relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath)) return null;

        var combined = Path.GetFullPath(Path.Combine(_root, relativePath));

        // Refuse anything that escapes the uploads root.
        if (!combined.StartsWith(Path.GetFullPath(_root), StringComparison.OrdinalIgnoreCase))
            return null;

        return File.Exists(combined) ? combined : null;
    }

    public void Delete(string? relativePath)
    {
        var path = ResolvePath(relativePath);
        if (path is null) return;
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
            // A file we cannot remove is not worth failing the request over.
        }
    }

    private static string SanitiseFolder(string folder)
    {
        var cleaned = new string(folder.Where(c => char.IsLetterOrDigit(c) || c is '-' or '_').ToArray());
        return string.IsNullOrEmpty(cleaned) ? "misc" : cleaned;
    }
}
