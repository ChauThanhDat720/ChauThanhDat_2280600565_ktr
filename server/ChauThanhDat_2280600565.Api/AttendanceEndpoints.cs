using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ChauThanhDat_2280600565.Api.Services;
using static Attendance.Api.AuthEndpoints;
using static Attendance.Api.ManagementEndpoints;

namespace Attendance.Api;

public static class AttendanceEndpoints
{
    public static void MapAttendance(this WebApplication app)
    {
        var lessons = app.MapGroup("/api/lessons").RequireAuthorization();

        // Lấy danh sách buổi học
        lessons.MapGet("/", async (AppDb db, ClaimsPrincipal user) =>
        {
            var visibleCourseIds = await VisibleCourses(db, user).Select(c => c.Id).ToListAsync();
            var result = await db.Lessons
                .AsNoTracking()
                .Where(x => visibleCourseIds.Contains(x.CourseId))
                .OrderByDescending(x => x.StartsAt)
                .Select(l => new 
                { 
                    l.Id, 
                    l.CourseId, 
                    l.Title, 
                    l.StartsAt, 
                    l.EndsAt, 
                    l.Latitude, 
                    l.Longitude, 
                    l.RadiusMeters, 
                    l.Closed 
                })
                .ToListAsync();

            return Results.Ok(result);
        });

        // Tạo buổi học mới
        lessons.MapPost("/", async (LessonInput input, AppDb db, ClaimsPrincipal user) =>
        {
            if (!await db.Courses.AnyAsync(x => x.Id == input.CourseId))
                return Error("Không tìm thấy lớp.", 404);

            if (!await CanManage(db, user, input.CourseId))
                return Results.Forbid();

            if (!ValidLesson(input))
                return Error("Kiểm tra thời gian, tọa độ và bán kính (10–500 mét, tối đa 12 giờ).");

            var lesson = new Lesson();
            ApplyLesson(lesson, input);

            db.Lessons.Add(lesson);
            Security.Audit(db, user, "lesson.create", lesson.Id);
            await db.SaveChangesAsync();

            return Results.Created($"/api/lessons/{lesson.Id}", PublicLesson(lesson));
        }).RequireAuthorization("staff");

        // Cập nhật buổi học
        lessons.MapPut("/{id:guid}", async (Guid id, LessonInput input, AppDb db, ClaimsPrincipal user) =>
        {
            var lesson = await db.Lessons.FindAsync(id);
            if (lesson is null)
                return Error("Không tìm thấy buổi học.", 404);

            if (!await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            if (input.CourseId != lesson.CourseId || !ValidLesson(input))
                return Error("Thông tin buổi học không hợp lệ; không thể chuyển lớp.");

            ApplyLesson(lesson, input);
            lesson.QrCode = "";
            Security.Audit(db, user, "lesson.update", id);
            await db.SaveChangesAsync();

            return Results.Ok(PublicLesson(lesson));
        }).RequireAuthorization("staff");

        // Xóa buổi học
        lessons.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            var lesson = await db.Lessons.FindAsync(id);
            if (lesson is null)
                return Error("Không tìm thấy buổi học.", 404);

            if (!await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            db.Lessons.Remove(lesson);
            Security.Audit(db, user, "lesson.delete", id);
            await db.SaveChangesAsync();

            return Results.NoContent();
        }).RequireAuthorization("staff");

        // Tạo mã QR động cho buổi học
        lessons.MapPost("/{id:guid}/qr", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            var lesson = await db.Lessons.FindAsync(id);
            if (lesson is null)
                return Error("Không tìm thấy buổi học.", 404);

            if (!await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            var now = DateTimeOffset.UtcNow;
            if (lesson.Closed || now < lesson.StartsAt || now >= lesson.EndsAt)
                return Error("Buổi học chưa mở hoặc đã kết thúc.");

            lesson.QrCode = Security.Token();
            lesson.QrExpiresAt = now.AddSeconds(60) < lesson.EndsAt ? now.AddSeconds(60) : lesson.EndsAt;

            await db.SaveChangesAsync();
            return Results.Ok(new { lessonId = id, code = lesson.QrCode, expiresAt = lesson.QrExpiresAt });
        }).RequireAuthorization("staff");

        var attendance = app.MapGroup("/api/attendance").RequireAuthorization();

        // Xem lịch sử điểm danh
        attendance.MapGet("/", async (AppDb db, ClaimsPrincipal user, Guid? lessonId) =>
        {
            var query = db.AttendanceRecords.AsNoTracking().AsQueryable();

            if (user.IsInRole("student"))
            {
                query = query.Where(x => x.StudentId == user.UserId());
            }
            else if (!user.Admin())
            {
                query = query.Where(x => db.Lessons.Any(l => l.Id == x.LessonId && db.Courses.Any(c => c.Id == l.CourseId && c.TeacherId == user.UserId())));
            }

            if (lessonId.HasValue)
            {
                query = query.Where(x => x.LessonId == lessonId.Value);
            }

            var records = await query.OrderByDescending(x => x.CheckedAt).ToListAsync();
            return Results.Ok(records);
        });

        // Sinh viên điểm danh (QR / Biometric / NFC / Manual kèm kiểm tra GPS)
        attendance.MapPost("/check-in", async (CheckInInput input, AppDb db, ClaimsPrincipal user, IAttendanceService attendanceSvc) =>
        {
            var lesson = await db.Lessons.FindAsync(input.LessonId);
            if (lesson is null)
                return Error("Không tìm thấy buổi học.", 404);

            var now = DateTimeOffset.UtcNow;
            if (lesson.Closed || now < lesson.StartsAt || now >= lesson.EndsAt)
                return Error("Ngoài thời gian điểm danh.");

            var studentId = user.UserId();
            var isEnrolled = await db.Enrollments.AnyAsync(e => e.CourseId == lesson.CourseId && e.StudentId == studentId);
            if (!isEnrolled)
                return Results.Forbid();

            // Kiểm tra tính hợp lệ của tọa độ GPS
            if (!Security.ValidCoordinates(input.Latitude, input.Longitude) 
                || !double.IsFinite(input.AccuracyMeters) 
                || input.AccuracyMeters is <= 0 or > 50
                || (now - input.PositionTime).TotalSeconds is > 60 or < -10)
            {
                return Error("Vị trí chưa đủ chính xác hoặc đã cũ. Hãy bật GPS và thử lại.");
            }

            var distance = await attendanceSvc.CalculateDistanceAsync(lesson.Latitude, lesson.Longitude, input.Latitude, input.Longitude);
            if (distance > lesson.RadiusMeters)
            {
                return Error($"Bạn cách lớp {Math.Round(distance)} m, ngoài bán kính {lesson.RadiusMeters} m.");
            }

            // Kiểm tra theo từng phương thức
            if (input.Method == "qr")
            {
                if (string.IsNullOrEmpty(input.Code) || lesson.QrCode != input.Code || lesson.QrExpiresAt <= now)
                    return Error("QR không hợp lệ hoặc hết hạn.");
            }
            else if (input.Method == "nfc")
            {
                var course = await db.Courses.FindAsync(lesson.CourseId);
                if (course == null || string.IsNullOrEmpty(course.NfcTagId) || course.NfcTagId != input.NfcTagId?.ToUpperInvariant())
                    return Error("Thẻ NFC không thuộc lớp này.");
            }
            else if (input.Method != "biometric" && input.Method != "manual")
            {
                return Error("Phương thức điểm danh không hợp lệ.");
            }

            if (await db.AttendanceRecords.AnyAsync(x => x.LessonId == lesson.Id && x.StudentId == studentId))
            {
                return Error("Bạn đã điểm danh buổi này.", 409);
            }

            var status = now > lesson.StartsAt.AddMinutes(15) ? "late" : "present";
            var record = new AttendanceRecord
            {
                LessonId = lesson.Id,
                StudentId = studentId,
                Method = input.Method,
                Latitude = input.Latitude,
                Longitude = input.Longitude,
                AccuracyMeters = input.AccuracyMeters,
                DistanceMeters = distance,
                Status = status
            };

            db.AttendanceRecords.Add(record);
            Security.Audit(db, user, "attendance.check-in", record.Id);
            await db.SaveChangesAsync();

            return Results.Created($"/api/attendance/{record.Id}", record);
        }).RequireAuthorization("student");

        // Giáo viên điểm danh thủ công
        attendance.MapPost("/", async (AttendanceInput input, AppDb db, ClaimsPrincipal user) =>
        {
            var lesson = await db.Lessons.FindAsync(input.LessonId);
            if (lesson is null)
                return Error("Không tìm thấy buổi học.", 404);

            if (!await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            if (!ValidAttendance(input) || !await db.Enrollments.AnyAsync(x => x.CourseId == lesson.CourseId && x.StudentId == input.StudentId))
                return Error("Sinh viên hoặc trạng thái không hợp lệ.");

            if (await db.AttendanceRecords.AnyAsync(x => x.LessonId == input.LessonId && x.StudentId == input.StudentId))
                return Error("Đã có bản ghi điểm danh.", 409);

            var record = new AttendanceRecord
            {
                LessonId = input.LessonId,
                StudentId = input.StudentId,
                Method = "manual",
                Status = input.Status,
                Note = Security.Sanitize(input.Note)
            };

            db.AttendanceRecords.Add(record);
            Security.Audit(db, user, "attendance.create", record.Id);
            await db.SaveChangesAsync();

            return Results.Created($"/api/attendance/{record.Id}", record);
        }).RequireAuthorization("staff");

        // Giáo viên chỉnh sửa trạng thái điểm danh
        attendance.MapPut("/{id:guid}", async (Guid id, AttendanceInput input, AppDb db, ClaimsPrincipal user) =>
        {
            var record = await db.AttendanceRecords.FindAsync(id);
            if (record is null)
                return Error("Không tìm thấy điểm danh.", 404);

            var lesson = await db.Lessons.FindAsync(record.LessonId);
            if (lesson == null || !await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            if (input.StudentId != record.StudentId || input.LessonId != record.LessonId || !ValidAttendance(input))
                return Error("Chỉ được sửa trạng thái và ghi chú.");

            record.Status = input.Status;
            record.Note = Security.Sanitize(input.Note);
            Security.Audit(db, user, "attendance.update", id);
            await db.SaveChangesAsync();

            return Results.Ok(record);
        }).RequireAuthorization("staff");

        // Xóa bản ghi điểm danh
        attendance.MapDelete("/{id:guid}", async (Guid id, AppDb db, ClaimsPrincipal user) =>
        {
            var record = await db.AttendanceRecords.FindAsync(id);
            if (record is null)
                return Error("Không tìm thấy điểm danh.", 404);

            var lesson = await db.Lessons.FindAsync(record.LessonId);
            if (lesson == null || !await CanManage(db, user, lesson.CourseId))
                return Results.Forbid();

            db.AttendanceRecords.Remove(record);
            Security.Audit(db, user, "attendance.delete", id);
            await db.SaveChangesAsync();

            return Results.NoContent();
        }).RequireAuthorization("staff");
    }

    private static object PublicLesson(Lesson l) => new
    {
        l.Id,
        l.CourseId,
        l.Title,
        l.StartsAt,
        l.EndsAt,
        l.Latitude,
        l.Longitude,
        l.RadiusMeters,
        l.Closed
    };

    private static bool ValidLesson(LessonInput i) =>
        !string.IsNullOrWhiteSpace(i.Title)
        && i.Title.Length <= 150
        && i.EndsAt > i.StartsAt
        && (i.EndsAt - i.StartsAt).TotalHours <= 12
        && Security.ValidCoordinates(i.Latitude, i.Longitude)
        && double.IsFinite(i.RadiusMeters)
        && i.RadiusMeters is >= 10 and <= 500;

    private static void ApplyLesson(Lesson l, LessonInput i)
    {
        l.CourseId = i.CourseId;
        l.Title = Security.Sanitize(i.Title);
        l.StartsAt = i.StartsAt;
        l.EndsAt = i.EndsAt;
        l.Latitude = i.Latitude;
        l.Longitude = i.Longitude;
        l.RadiusMeters = i.RadiusMeters;
        l.Closed = i.Closed;
    }

    private static bool ValidAttendance(AttendanceInput i) =>
        i.Status is "present" or "late" or "absent" or "excused"
        && i.Note is { Length: <= 500 };
}
