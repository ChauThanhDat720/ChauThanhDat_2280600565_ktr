using Microsoft.EntityFrameworkCore;

namespace Attendance.Api;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Username { get; set; } = "";
    public string Email { get; set; } = "";
    public string Name { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string Role { get; set; } = "student";
    public bool Verified { get; set; }
    public int FailedLogins { get; set; }
    public DateTimeOffset? LockedUntil { get; set; }
    public object Public() => new { Id, Username, Email, Name, Role, Verified };
}

public class OtpChallenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Purpose { get; set; } = "";
    public string CodeHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public int Attempts { get; set; }
    public bool Used { get; set; }
}

public class LoginSession
{
    public int Id { get; set; }
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
}

public class Course
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string Room { get; set; } = "";
    public Guid TeacherId { get; set; }
    public string? NfcTagId { get; set; }
}

public class Enrollment
{
    public Guid CourseId { get; set; }
    public Guid StudentId { get; set; }
}

public class Lesson
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CourseId { get; set; }
    public string Title { get; set; } = "";
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset EndsAt { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; } = 100;
    public bool Closed { get; set; }
    public string QrCode { get; set; } = "";
    public DateTimeOffset QrExpiresAt { get; set; }
}

public class AttendanceRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid LessonId { get; set; }
    public Guid StudentId { get; set; }
    public DateTimeOffset CheckedAt { get; set; } = DateTimeOffset.UtcNow;
    public string Method { get; set; } = "";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double AccuracyMeters { get; set; }
    public double DistanceMeters { get; set; }
    public string Status { get; set; } = "present";
    public string Note { get; set; } = "";
}

public class AuditEntry
{
    public long Id { get; set; }
    public Guid ActorId { get; set; }
    public string Action { get; set; } = "";
    public string Target { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<OtpChallenge> OtpChallenges => Set<OtpChallenge>();
    public DbSet<LoginSession> LoginSessions => Set<LoginSession>();
    public DbSet<Course> Courses => Set<Course>();
    public DbSet<Enrollment> Enrollments => Set<Enrollment>();
    public DbSet<Lesson> Lessons => Set<Lesson>();
    public DbSet<AttendanceRecord> AttendanceRecords => Set<AttendanceRecord>();
    public DbSet<AuditEntry> AuditEntries => Set<AuditEntry>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>().HasIndex(x => x.Username).IsUnique();
        b.Entity<User>().HasIndex(x => x.Email).IsUnique();
        b.Entity<Course>().HasIndex(x => x.Code).IsUnique();
        b.Entity<Enrollment>().HasKey(x => new { x.CourseId, x.StudentId });
        b.Entity<AttendanceRecord>().HasIndex(x => new { x.LessonId, x.StudentId }).IsUnique();
        b.Entity<LoginSession>().HasIndex(x => x.TokenHash).IsUnique();
        b.Entity<Course>().HasOne<User>().WithMany().HasForeignKey(x => x.TeacherId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<Enrollment>().HasOne<Course>().WithMany().HasForeignKey(x => x.CourseId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<Enrollment>().HasOne<User>().WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<Lesson>().HasOne<Course>().WithMany().HasForeignKey(x => x.CourseId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<AttendanceRecord>().HasOne<Lesson>().WithMany().HasForeignKey(x => x.LessonId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<AttendanceRecord>().HasOne<User>().WithMany().HasForeignKey(x => x.StudentId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<OtpChallenge>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<LoginSession>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

public record RegisterInput(string Username, string Email, string Name, string Password);
public record LoginInput(string Username, string Password);
public record VerifyInput(Guid ChallengeId, string Code);
public record UserInput(string Username, string Email, string Name, string Role, string? Password);
public record CourseInput(string Code, string Name, string Room, Guid TeacherId, string? NfcTagId);
public record EnrollmentInput(Guid StudentId);
public record LessonInput(Guid CourseId, string Title, DateTimeOffset StartsAt, DateTimeOffset EndsAt,
    double Latitude, double Longitude, double RadiusMeters, bool Closed);
public record CheckInInput(Guid LessonId, string Method, string? Code, string? NfcTagId,
    double Latitude, double Longitude, double AccuracyMeters, DateTimeOffset PositionTime);
public record AttendanceInput(Guid StudentId, Guid LessonId, string Status, string Note);
