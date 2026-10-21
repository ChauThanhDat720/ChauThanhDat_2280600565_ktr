using System.Threading.RateLimiting;
using Attendance.Api;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Cấu hình Kestrel tối ưu bảo mật & chống DoS
builder.WebHost.ConfigureKestrel(options =>
{
    options.AddServerHeader = false; // Ẩn thông tin phiên bản server
    options.Limits.MaxRequestBodySize = 2 * 1024 * 1024; // Giới hạn kích thước payload tối đa 2MB
});

Directory.CreateDirectory("App_Data");
builder.Configuration.AddJsonFile("App_Data/smtp.local.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();
if (args.Length > 0) builder.Configuration.AddCommandLine(args);

builder.Services.AddDbContext<AppDb>(o => 
    o.UseSqlite(builder.Configuration.GetConnectionString("Database") ?? "Data Source=App_Data/chauthanhdat_2280600565.db"));

builder.Services.AddSingleton<PasswordHasher<User>>();
builder.Services.AddSingleton<Mailer>();
builder.Services.AddScoped<ChauThanhDat_2280600565.Api.Services.IAttendanceService, ChauThanhDat_2280600565.Api.Services.AttendanceService>();

builder.Services.AddAuthentication("token")
    .AddScheme<AuthenticationSchemeOptions, TokenAuthentication>("token", _ => { });

builder.Services.AddAuthorization(o =>
{
    o.AddPolicy("admin", p => p.RequireRole("admin"));
    o.AddPolicy("staff", p => p.RequireRole("admin", "teacher"));
    o.AddPolicy("student", p => p.RequireRole("student"));
});

// Giới hạn tần suất gọi API (Rate Limiting) chống Brute-force & DDoS
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.OnRejected = async (context, token) => 
        await context.HttpContext.Response.WriteAsJsonAsync(new 
        { 
            message = "Quá nhiều yêu cầu. Vui lòng thử lại sau một phút.",
            traceId = context.HttpContext.TraceIdentifier 
        }, token);

    o.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions 
        { 
            PermitLimit = 20, 
            Window = TimeSpan.FromMinutes(1), 
            QueueLimit = 0 
        }));
});

var app = builder.Build();
Directory.CreateDirectory("App_Data");

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    await db.Database.EnsureCreatedAsync();
    var password = builder.Configuration["Bootstrap:AdminPassword"];
    if (!await db.Users.AnyAsync(x => x.Role == "admin") && !string.IsNullOrEmpty(password))
    {
        if (!Security.ValidPassword(password)) throw new InvalidOperationException("Bootstrap:AdminPassword không đủ mạnh.");
        var email = builder.Configuration["Bootstrap:AdminEmail"]?.Trim().ToLowerInvariant();
        if (!Security.ValidEmail(email)) throw new InvalidOperationException("Cần Bootstrap:AdminEmail hợp lệ.");
        var username = builder.Configuration["Bootstrap:AdminUsername"]?.Trim().ToLowerInvariant() ?? "admin";
        if (!Security.ValidUsername(username)) throw new InvalidOperationException("Bootstrap:AdminUsername không hợp lệ.");
        var u = new User { Username = username, Email = email!, Name = "Quản trị viên", Role = "admin", Verified = true };
        u.PasswordHash = scope.ServiceProvider.GetRequiredService<PasswordHasher<User>>().HashPassword(u, password);
        db.Users.Add(u); 
        await db.SaveChangesAsync();
    }
}

// Middleware: Tối ưu Bảo mật (HTTP Security Headers) & Kiểm soát lỗi toàn cục
app.Use(async (context, next) =>
{
    // Áp dụng các HTTP Security Headers tiêu chuẩn OWASP
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate";
    context.Response.Headers["Pragma"] = "no-cache";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["X-XSS-Protection"] = "1; mode=block";
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    context.Response.Headers["Permissions-Policy"] = "geolocation=(self), camera=(self), microphone=(self)";

    try 
    { 
        await next(context); 
    }
    catch (BadHttpRequestException e) when (!context.Response.HasStarted)
    {
        context.Response.StatusCode = e.StatusCode;
        await context.Response.WriteAsJsonAsync(new 
        { 
            message = "Dữ liệu yêu cầu không hợp lệ hoặc vượt quá kích thước cho phép.",
            traceId = context.TraceIdentifier
        });
    }
    catch (UnauthorizedAccessException) when (!context.Response.HasStarted)
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        await context.Response.WriteAsJsonAsync(new 
        { 
            message = "Bạn không có quyền thực hiện thao tác này.",
            traceId = context.TraceIdentifier
        });
    }
    catch (KeyNotFoundException) when (!context.Response.HasStarted)
    {
        context.Response.StatusCode = StatusCodes.Status404NotFound;
        await context.Response.WriteAsJsonAsync(new 
        { 
            message = "Không tìm thấy dữ liệu yêu cầu.",
            traceId = context.TraceIdentifier
        });
    }
    catch (DbUpdateException e) when (e.InnerException is Microsoft.Data.Sqlite.SqliteException { SqliteErrorCode: 19 })
    {
        context.Response.StatusCode = StatusCodes.Status409Conflict;
        await context.Response.WriteAsJsonAsync(new 
        { 
            message = "Dữ liệu trùng lặp hoặc đang được sử dụng.",
            traceId = context.TraceIdentifier
        });
    }
    catch (Exception e) when (e is not OperationCanceledException && !context.Response.HasStarted)
    {
        app.Logger.LogError(e, "[{TraceId}] Lỗi xử lý yêu cầu: {Method} {Path}", context.TraceIdentifier, context.Request.Method, context.Request.Path);
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        await context.Response.WriteAsJsonAsync(new 
        { 
            message = "Không thể xử lý yêu cầu. Kiểm tra cấu hình máy chủ hoặc thử lại.",
            traceId = context.TraceIdentifier
        });
    }
});

if (!app.Environment.IsDevelopment()) 
{ 
    app.UseHsts(); 
    app.UseHttpsRedirection(); 
}

app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "ChauThanhDat_2280600565 API" }));
app.MapAuth();
app.MapManagement();
app.MapAttendance();

app.Run();
