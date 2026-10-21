using System.Net;
using System.Net.Mail;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Attendance.Api;

public static class Security
{
    public static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    public static string Token() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public static string OtpHash(Guid id, string code) => Hash($"{id}:{code}");
    public static Guid UserId(this ClaimsPrincipal p) => Guid.Parse(p.FindFirstValue(ClaimTypes.NameIdentifier)!);
    public static bool Admin(this ClaimsPrincipal p) => p.IsInRole("admin");
    
    public static bool ValidPassword(string? p) => 
        p is { Length: >= 10 and <= 128 }
        && p.Any(char.IsUpper) 
        && p.Any(char.IsLower) 
        && p.Any(char.IsDigit);

    public static bool ValidUsername(string? p) => 
        p is { Length: >= 3 and <= 40 }
        && p.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '.' or '-');

    public static bool ValidEmail(string? email) => 
        email is { Length: <= 254 }
        && MailAddress.TryCreate(email, out var a) 
        && a.Address == email;

    public static bool ValidCoordinates(double lat, double lon) => 
        double.IsFinite(lat) 
        && double.IsFinite(lon)
        && lat is >= -90 and <= 90 
        && lon is >= -180 and <= 180;

    public static double Distance(double lat1, double lon1, double lat2, double lon2)
    {
        const double rad = Math.PI / 180;
        var a = Math.Pow(Math.Sin((lat2 - lat1) * rad / 2), 2)
            + Math.Cos(lat1 * rad) * Math.Cos(lat2 * rad) * Math.Pow(Math.Sin((lon2 - lon1) * rad / 2), 2);
        return 6371000 * 2 * Math.Atan2(Math.Sqrt(Math.Clamp(a, 0, 1)), Math.Sqrt(Math.Clamp(1 - a, 0, 1)));
    }

    public static void Audit(AppDb db, ClaimsPrincipal actor, string action, object target) => 
        db.AuditEntries.Add(new AuditEntry { ActorId = actor.UserId(), Action = action, Target = target.ToString()! });

    public static string Sanitize(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        var trimmed = text.Trim();
        var sb = new StringBuilder(trimmed.Length);
        foreach (var ch in trimmed)
        {
            if (!char.IsControl(ch) || ch is '\r' or '\n' or '\t')
            {
                sb.Append(ch);
            }
        }
        return sb.ToString();
    }
}

public class TokenAuthentication(
    IOptionsMonitor<AuthenticationSchemeOptions> options, 
    ILoggerFactory logger,
    UrlEncoder encoder, 
    AppDb db) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) 
            return AuthenticateResult.NoResult();

        var token = header[7..].Trim();
        if (string.IsNullOrEmpty(token) || token.Length > 256) 
            return AuthenticateResult.Fail("Phiên đăng nhập không hợp lệ.");

        var hash = Security.Hash(token);
        var session = await db.LoginSessions.AsNoTracking().SingleOrDefaultAsync(s => s.TokenHash == hash);
        if (session is null || session.ExpiresAt <= DateTimeOffset.UtcNow) 
            return AuthenticateResult.Fail("Phiên đăng nhập hết hạn.");

        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(u => u.Id == session.UserId);
        if (user is null || !user.Verified) 
            return AuthenticateResult.Fail("Tài khoản không hợp lệ.");

        var identity = new ClaimsIdentity(new[] 
        { 
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Name, user.Name), 
            new Claim(ClaimTypes.Role, user.Role) 
        }, Scheme.Name);

        return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name));
    }
}

public class Mailer(IConfiguration config, IWebHostEnvironment env)
{
    public async Task<string> SendAsync(string email, string otp, string purpose, Guid challengeId)
    {
        using var message = new MailMessage(config["Smtp:From"] ?? "attendance@localhost", email)
        {
            Subject = purpose == "register" ? "Attendly — Xác thực email" : "Attendly — Mã đăng nhập",
            Body = $"Mã OTP của bạn: {otp}\nHiệu lực 5 phút. Không chia sẻ mã này.\nMã yêu cầu: {challengeId}"
        };

        var host = config["Smtp:Host"];
        if (string.IsNullOrWhiteSpace(host))
        {
            if (!env.IsDevelopment()) 
                throw new InvalidOperationException("Cần cấu hình SMTP ngoài môi trường Development.");

            var path = Path.GetFullPath(config["Mail:PickupPath"] ?? "server/ChauThanhDat_2280600565.Api/App_Data/mail");
            Directory.CreateDirectory(path);

            using var pickup = new SmtpClient 
            { 
                DeliveryMethod = SmtpDeliveryMethod.SpecifiedPickupDirectory,
                PickupDirectoryLocation = path 
            };
            await pickup.SendMailAsync(message);
            return "pickup";
        }

        using var smtp = new SmtpClient(host, config.GetValue("Smtp:Port", 587))
        {
            EnableSsl = config.GetValue("Smtp:EnableSsl", true),
            Credentials = new NetworkCredential(config["Smtp:Username"], config["Smtp:Password"])
        };

        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        await smtp.SendMailAsync(message, timeout.Token);
        return "smtp";
    }
}

public static class AuthEndpoints
{
    public static void MapAuth(this WebApplication app)
    {
        var group = app.MapGroup("/api/auth").RequireRateLimiting("auth");

        // Đăng ký tài khoản
        group.MapPost("/register", async (RegisterInput input, AppDb db, Mailer mail, PasswordHasher<User> hasher) =>
        {
            var username = input.Username?.Trim().ToLowerInvariant() ?? "";
            var email = input.Email?.Trim().ToLowerInvariant() ?? "";

            if (!Security.ValidUsername(username) || !Security.ValidEmail(email) || string.IsNullOrWhiteSpace(input.Name)
                || input.Name.Length > 100 || !Security.ValidPassword(input.Password))
            {
                return Error("Tên đăng nhập 3–40 ký tự; mật khẩu 10–128 ký tự, có chữ hoa, thường và số. Kiểm tra email và họ tên.");
            }

            var user = await db.Users.SingleOrDefaultAsync(x => x.Username == username || x.Email == email);
            if (user is not null)
            {
                if (user.Verified || user.Username != username || user.Email != email
                    || hasher.VerifyHashedPassword(user, user.PasswordHash, input.Password) == PasswordVerificationResult.Failed)
                {
                    return Error("Tên đăng nhập hoặc email đã được sử dụng.", 409);
                }
            }
            else
            {
                user = new User { Username = username, Email = email, Name = input.Name.Trim() };
                user.PasswordHash = hasher.HashPassword(user, input.Password);
                db.Users.Add(user);
                await db.SaveChangesAsync();
            }

            return await Challenge(user, "register", db, mail);
        });

        // Đăng nhập
        group.MapPost("/login", async (LoginInput input, AppDb db, PasswordHasher<User> hasher, Mailer mail) =>
        {
            if (string.IsNullOrWhiteSpace(input.Username) || string.IsNullOrEmpty(input.Password) || input.Password.Length > 128)
                return Error("Sai tên đăng nhập hoặc mật khẩu.", 401);

            var username = input.Username.Trim().ToLowerInvariant();
            var user = await db.Users.SingleOrDefaultAsync(x => x.Username == username);
            if (user is null) 
                return Error("Sai tên đăng nhập hoặc mật khẩu.", 401);

            if (user.LockedUntil > DateTimeOffset.UtcNow) 
                return Error("Tạm khóa đăng nhập. Thử lại sau 15 phút.", 429);

            if (hasher.VerifyHashedPassword(user, user.PasswordHash, input.Password) == PasswordVerificationResult.Failed)
            {
                user.FailedLogins++;
                if (user.FailedLogins >= 5) 
                { 
                    user.LockedUntil = DateTimeOffset.UtcNow.AddMinutes(15); 
                    user.FailedLogins = 0; 
                }
                await db.SaveChangesAsync();
                return Error("Sai tên đăng nhập hoặc mật khẩu.", 401);
            }

            user.FailedLogins = 0;
            user.LockedUntil = null;
            await db.SaveChangesAsync();

            // Giáo viên đã xác thực vào thẳng Dashboard mà không cần OTP
            if (user.Role == "teacher" && user.Verified)
            {
                var session = CreateSession(user, db);
                await db.SaveChangesAsync();
                return Results.Ok(session);
            }

            return await Challenge(user, user.Verified ? "login" : "register", db, mail);
        });

        // Xác thực mã OTP
        group.MapPost("/verify", async (VerifyInput input, AppDb db) =>
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            var challenge = await db.OtpChallenges.FindAsync(input.ChallengeId);
            if (challenge is null || challenge.Used || challenge.ExpiresAt <= DateTimeOffset.UtcNow || challenge.Attempts >= 5)
            {
                return Error("OTP hết hạn hoặc đã được sử dụng. Vui lòng đăng nhập lại.");
            }

            challenge.Attempts++;
            if (input.Code is null || input.Code.Length != 6 || !CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(challenge.CodeHash), Encoding.UTF8.GetBytes(Security.OtpHash(challenge.Id, input.Code))))
            {
                await db.SaveChangesAsync();
                await transaction.CommitAsync();
                return Error("Mã OTP không đúng.");
            }

            var user = await db.Users.FindAsync(challenge.UserId);
            if (user is null) 
                return Error("Tài khoản không tồn tại.");

            challenge.Used = true;
            user.Verified = true;
            var session = CreateSession(user, db);

            await db.SaveChangesAsync();
            await transaction.CommitAsync();

            return Results.Ok(session);
        });

        // Thông tin người dùng hiện tại
        app.MapGet("/api/auth/me", async (ClaimsPrincipal p, AppDb db) =>
        {
            var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(u => u.Id == p.UserId());
            return user != null ? Results.Ok(user.Public()) : Results.NotFound();
        }).RequireAuthorization();

        // Đăng xuất
        app.MapPost("/api/auth/logout", async (HttpContext context, AppDb db) =>
        {
            var authHeader = context.Request.Headers.Authorization.ToString();
            if (authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            {
                var hash = Security.Hash(authHeader[7..]);
                await db.LoginSessions.Where(x => x.TokenHash == hash).ExecuteDeleteAsync();
            }
            return Results.NoContent();
        }).RequireAuthorization();
    }

    private static object CreateSession(User user, AppDb db)
    {
        var token = Security.Token();
        var expiresAt = DateTimeOffset.UtcNow.AddHours(12);
        db.LoginSessions.Add(new LoginSession 
        { 
            UserId = user.Id, 
            TokenHash = Security.Hash(token), 
            ExpiresAt = expiresAt 
        });
        return new { token, expiresAt, user = user.Public() };
    }

    private static async Task<IResult> Challenge(User user, string purpose, AppDb db, Mailer mail)
    {
        var otp = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
        var challenge = new OtpChallenge 
        { 
            UserId = user.Id, 
            Purpose = purpose, 
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5) 
        };
        challenge.CodeHash = Security.OtpHash(challenge.Id, otp);

        string deliveryMode;
        try 
        { 
            deliveryMode = await mail.SendAsync(user.Email, otp, purpose, challenge.Id); 
        }
        catch (Exception e) when (e is SmtpException or OperationCanceledException or InvalidOperationException)
        {
            return Error("Chưa gửi được email OTP. Người quản trị cần kiểm tra cấu hình email gửi và kết nối mạng máy chủ, rồi gửi mã lại.", 503);
        }

        // Đánh dấu các challenge chưa dùng trước đó thành đã dùng
        await db.OtpChallenges
            .Where(x => x.UserId == user.Id && !x.Used)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.Used, true));

        db.OtpChallenges.Add(challenge);
        await db.SaveChangesAsync();

        return Results.Ok(new 
        { 
            challengeId = challenge.Id, 
            expiresAt = challenge.ExpiresAt, 
            deliveryMode,
            message = deliveryMode == "smtp" 
                ? "Mã OTP đã được gửi đến email đã đăng ký. Mã có hiệu lực 5 phút."
                : "Bản thử nghiệm đang lưu email trên máy chủ. Mã chưa được gửi đến hộp thư. Nhờ người chạy bản thử cung cấp mã; mã có hiệu lực 5 phút." 
        });
    }

    public static IResult Error(string message, int status = 400) => Results.Json(new { message }, statusCode: status);
}
