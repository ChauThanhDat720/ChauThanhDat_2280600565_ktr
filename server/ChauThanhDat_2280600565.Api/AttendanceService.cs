using Microsoft.EntityFrameworkCore;

namespace ChauThanhDat_2280600565.Api.Services;

using Attendance.Api;

public interface IAttendanceService
{
    Task<List<Lesson>> GetVisibleLessonsAsync(Guid userId, bool isAdmin, bool isStudent);
    Task<Lesson?> GetLessonByIdAsync(Guid lessonId);
    Task<double> CalculateDistanceAsync(double lat1, double lon1, double lat2, double lon2);
}

public class AttendanceService(AppDb db) : IAttendanceService
{
    public async Task<List<Lesson>> GetVisibleLessonsAsync(Guid userId, bool isAdmin, bool isStudent)
    {
        IQueryable<Course> coursesQuery = db.Courses.AsQueryable();
        if (isStudent)
        {
            coursesQuery = coursesQuery.Where(c => db.Enrollments.Any(e => e.CourseId == c.Id && e.StudentId == userId));
        }
        else if (!isAdmin)
        {
            coursesQuery = coursesQuery.Where(c => c.TeacherId == userId);
        }

        var courseIds = await coursesQuery.Select(c => c.Id).ToListAsync();
        return await db.Lessons
            .Where(l => courseIds.Contains(l.CourseId))
            .OrderByDescending(l => l.StartsAt)
            .ToListAsync();
    }

    public async Task<Lesson?> GetLessonByIdAsync(Guid lessonId)
    {
        return await db.Lessons.FindAsync(lessonId);
    }

    public Task<double> CalculateDistanceAsync(double lat1, double lon1, double lat2, double lon2)
    {
        return Task.FromResult(Security.Distance(lat1, lon1, lat2, lon2));
    }
}
