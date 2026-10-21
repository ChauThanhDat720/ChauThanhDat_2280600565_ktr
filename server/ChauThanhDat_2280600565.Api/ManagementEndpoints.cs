using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using static Attendance.Api.AuthEndpoints;

namespace Attendance.Api;

public static class ManagementEndpoints
{
    public static async Task<bool> CanManage(AppDb db, ClaimsPrincipal user, Guid courseId)
    {
        if (user.Admin()) return true;
        return await db.Courses.AnyAsync(x => x.Id == courseId && x.TeacherId == user.UserId());
    }

    public static IQueryable<Course> VisibleCourses(AppDb db, ClaimsPrincipal user)
    {
        if (user.Admin()) return db.Courses;
        if (user.IsInRole("teacher")) return db.Courses.Where(x => x.TeacherId == user.UserId());
        return db.Courses.Where(x => db.Enrollments.Any(e => e.CourseId == x.Id && e.StudentId == user.UserId()));
    }

    public static void MapManagement(this WebApplication app)
    {
        var users = app.MapGroup("/api/users").RequireAuthorization("admin");

        // Quản lý người dùng: Lấy danh sách
        users.MapGet("/", async (AppDb db) =>
        {
            var userList = await db.Users
                .AsNoTracking()
                .OrderBy(x => x.Name)
                .ToListAsync();

            return Results.Ok(userList.Select(x => x.Public()));
        });

        // Tạo người dùng mới
        users.MapPost("/", async (UserInput input, AppDb db, ClaimsPrincipal user, PasswordHasher<User> hasher) =>
        {
            if (!ValidUser(input) || !Security.ValidPassword(input.Password))
                return Error("Thông tin không hợp lệ; mật khẩu cần 10–128 ký tự, chữ hoa, thường và số.");

            var username = input.Username.Trim().ToLowerInvariant();
            var email = input.Email.Trim().ToLowerInvariant();

            if (await db.Users.AnyAsync(x => x.Username == username || x.Email == email))
                return Error("Tên đăng nhập hoặc email đã tồn tại.", 409);

            var newUser = new User
            {
                Username = username,
                Email = email,
                Name = Security.Sanitize(input.Name),
                Role = input.Role,
                Verified = true
            };

            newUser.PasswordHash = hasher.HashPassword(newUser, input.Password!);
            db.Users.Add(newUser);
            Security.Audit(db, user, "user.create", newUser.Id);
            await db.SaveChangesAsync();

            return Results.Created($"/api/users/{newUser.Id}", newUser.Public());
        });

        // Cập nhật thông tin người dùng
        users.MapPut("/{id:guid}", async (Guid id, UserInput input, AppDb db, ClaimsPrincipal user, PasswordHasher<User> hasher) =>
        {
            var existingUser = await db.Users.FindAsync(id);
            if (existingUser is null)
                return Error("Không tìm thấy tài khoản.", 404);

            if (!ValidUser(input) || (!string.IsNullOrEmpty(input.Password) && !Security.ValidPassword(input.Password)))
                return Error("Thông tin tài khoản không hợp lệ.");

            if (id == user.UserId() && input.Role != "admin")
                return Error("Không thể tự hạ quyền quản trị.");

            if (existingUser.Role == "teacher" && input.Role != "teacher" && await db.Courses.AnyAsync(x => x.TeacherId == id))
                return Error("Chuyển các lớp sang giáo viên khác trước khi đổi vai trò.");

            if (existingUser.Role == "student" && input.Role != "student" && await db.Enrollments.AnyAsync(x => x.StudentId == id))
                return Error("Xóa sinh viên khỏi các lớp trước khi đổi vai trò.");

            var username = input.Username.Trim().ToLowerInvariant();
            var email = input.Email.Trim().ToLowerInvariant();

            if (await db.Users.AnyAsync(x => x.Id != id && (x.Username == username || x.Email == email)))
                return Error("Tên đăng nhập hoặc email đã tồn tại.", 409);

            existingUser.Username = username;
            existingUser.Email = email;
            existingUser.Name = Security.Sanitize(input.Name);
            existingUser.Role = input.Role;

            if (!string.IsNullOrEmpty(input.Password))
                existingUser.PasswordHash = hasher.HashPassword(existingUser, input.Password);

            await db.LoginSessions.Where(x => x.UserId == id).ExecuteDeleteAsync();
            await db.OtpChallenges.Where(x => x.UserId == id).ExecuteDeleteAsync();

            Security.Audit(db, user, "user.update", id);
            await db.SaveChangesAsync();

            return Results.Ok(existingUser.Public());
        });

        // Xóa người dùng
        users.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            if (id == user.UserId())
                return Error("Không thể xóa tài khoản đang sử dụng.");

            if (await db.Courses.AnyAsync(x => x.TeacherId == id))
                return Error("Chuyển các lớp sang giáo viên khác trước khi xóa.");

            var targetUser = await db.Users.FindAsync(id);
            if (targetUser is null)
                return Error("Không tìm thấy tài khoản.", 404);

            db.Users.Remove(targetUser);
            Security.Audit(db, user, "user.delete", id);
            await db.SaveChangesAsync();

            return Results.NoContent();
        });

        // Nhật ký kiểm toán hệ thống
        app.MapGet("/api/audit", async (AppDb db) =>
        {
            var auditEntries = await db.AuditEntries
                .AsNoTracking()
                .OrderByDescending(x => x.Id)
                .Take(200)
                .ToListAsync();

            return Results.Ok(auditEntries);
        }).RequireAuthorization("admin");

        var courses = app.MapGroup("/api/courses").RequireAuthorization();

        // Danh sách lớp học
        courses.MapGet("/", async (AppDb db, ClaimsPrincipal user) =>
        {
            var list = await VisibleCourses(db, user)
                .AsNoTracking()
                .OrderBy(x => x.Code)
                .ToListAsync();

            if (user.IsInRole("student"))
            {
                return Results.Ok(list.Select(c => new { c.Id, c.Code, c.Name, c.Room, c.TeacherId }));
            }

            return Results.Ok(list);
        });

        // Tạo lớp học mới
        courses.MapPost("/", async (CourseInput input, AppDb db, ClaimsPrincipal user) =>
        {
            if (!user.Admin() && input.TeacherId != user.UserId())
                return Results.Forbid();

            if (!await ValidCourse(db, input))
                return Error("Kiểm tra mã lớp, tên lớp, phòng và tài khoản giáo viên.");

            var courseCode = input.Code.Trim().ToUpperInvariant();
            if (await db.Courses.AnyAsync(x => x.Code == courseCode))
                return Error("Mã lớp đã tồn tại.", 409);

            var newCourse = new Course();
            ApplyCourse(newCourse, input);

            db.Courses.Add(newCourse);
            Security.Audit(db, user, "course.create", newCourse.Id);
            await db.SaveChangesAsync();

            return Results.Created($"/api/courses/{newCourse.Id}", newCourse);
        }).RequireAuthorization("staff");

        // Cập nhật thông tin lớp học
        courses.MapPut("/{id:guid}", async (Guid id, CourseInput input, AppDb db, ClaimsPrincipal user) =>
        {
            var course = await db.Courses.FindAsync(id);
            if (course is null)
                return Error("Không tìm thấy lớp.", 404);

            if (!await CanManage(db, user, id) || (!user.Admin() && input.TeacherId != user.UserId()))
                return Results.Forbid();

            if (!await ValidCourse(db, input))
                return Error("Thông tin lớp không hợp lệ.");

            var courseCode = input.Code.Trim().ToUpperInvariant();
            if (await db.Courses.AnyAsync(x => x.Id != id && x.Code == courseCode))
                return Error("Mã lớp đã tồn tại.", 409);

            ApplyCourse(course, input);
            Security.Audit(db, user, "course.update", id);
            await db.SaveChangesAsync();

            return Results.Ok(course);
        }).RequireAuthorization("staff");

        // Xóa lớp học
        courses.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            var course = await db.Courses.FindAsync(id);
            if (course is null)
                return Error("Không tìm thấy lớp.", 404);

            if (!await CanManage(db, user, id))
                return Results.Forbid();

            db.Courses.Remove(course);
            Security.Audit(db, user, "course.delete", id);
            await db.SaveChangesAsync();

            return Results.NoContent();
        }).RequireAuthorization("staff");

        // Danh sách sinh viên đã tham gia lớp
        courses.MapGet("/{id:guid}/students", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            if (!await CanManage(db, user, id))
                return Results.Forbid();

            var students = await db.Users
                .AsNoTracking()
                .Where(x => db.Enrollments.Any(e => e.CourseId == id && e.StudentId == x.Id))
                .ToListAsync();

            return Results.Ok(students.Select(x => x.Public()));
        }).RequireAuthorization("staff");

        // Danh sách sinh viên khả dụng để thêm vào lớp
        courses.MapGet("/{id:guid}/candidates", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            if (!await CanManage(db, user, id))
                return Results.Forbid();

            var candidates = await db.Users
                .AsNoTracking()
                .Where(x => x.Role == "student" && x.Verified && !db.Enrollments.Any(e => e.CourseId == id && e.StudentId == x.Id))
                .Select(x => new { x.Id, x.Username, x.Name })
                .ToListAsync();

            return Results.Ok(candidates);
        }).RequireAuthorization("staff");

        // Thêm sinh viên vào lớp
        courses.MapPost("/{id:guid}/students", async (Guid id, EnrollmentInput input, AppDb db, ClaimsPrincipal user) =>
        {
            if (!await CanManage(db, user, id))
                return Results.Forbid();

            if (!await db.Courses.AnyAsync(x => x.Id == id))
                return Error("Không tìm thấy lớp.", 404);

            if (!await db.Users.AnyAsync(x => x.Id == input.StudentId && x.Role == "student" && x.Verified))
                return Error("Sinh viên chưa xác thực hoặc không tồn tại.");

            if (await db.Enrollments.AnyAsync(x => x.CourseId == id && x.StudentId == input.StudentId))
                return Error("Sinh viên đã ở trong lớp.", 409);

            db.Enrollments.Add(new Enrollment { CourseId = id, StudentId = input.StudentId });
            Security.Audit(db, user, "enrollment.create", $"{id}/{input.StudentId}");
            await db.SaveChangesAsync();

            return Results.NoContent();
        }).RequireAuthorization("staff");

        // Xóa sinh viên khỏi lớp
        courses.MapDelete("/{id:guid}/students/{studentId:guid}", async (Guid id, Guid studentId, AppDb db, ClaimsPrincipal user) =>
        {
            if (!await CanManage(db, user, id))
                return Results.Forbid();

            var enrollment = await db.Enrollments.FindAsync(id, studentId);
            if (enrollment is null)
                return Error("Sinh viên không ở trong lớp.", 404);

            db.Enrollments.Remove(enrollment);
            Security.Audit(db, user, "enrollment.delete", $"{id}/{studentId}");
            await db.SaveChangesAsync();

            return Results.NoContent();
        }).RequireAuthorization("staff");
    }

    private static bool ValidUser(UserInput i) =>
        Security.ValidUsername(i.Username?.Trim())
        && Security.ValidEmail(i.Email?.Trim())
        && !string.IsNullOrWhiteSpace(i.Name)
        && i.Name.Length <= 100
        && i.Role is "admin" or "teacher" or "student";

    private static async Task<bool> ValidCourse(AppDb db, CourseInput i) =>
        !string.IsNullOrWhiteSpace(i.Code)
        && i.Code.Length <= 30
        && !string.IsNullOrWhiteSpace(i.Name)
        && i.Name.Length <= 150
        && i.Room is { Length: <= 100 }
        && (string.IsNullOrEmpty(i.NfcTagId) || (i.NfcTagId.Length is >= 8 and <= 64 && i.NfcTagId.All(Uri.IsHexDigit)))
        && await db.Users.AnyAsync(x => x.Id == i.TeacherId && x.Role == "teacher" && x.Verified);

    private static void ApplyCourse(Course c, CourseInput i)
    {
        c.Code = i.Code.Trim().ToUpperInvariant();
        c.Name = Security.Sanitize(i.Name);
        c.Room = Security.Sanitize(i.Room);
        c.TeacherId = i.TeacherId;
        c.NfcTagId = i.NfcTagId?.Trim().ToUpperInvariant();
    }
}
