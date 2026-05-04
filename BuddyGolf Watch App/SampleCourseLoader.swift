import Foundation

enum SampleCourseLoader {
    static func loadCourses(bundle: Bundle = .main) -> [Course] {
        guard let url = bundle.url(forResource: "sample_courses", withExtension: "json") else {
            assertionFailure("Missing bundled sample_courses.json")
            return [fallbackCourse]
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode([Course].self, from: data)
        } catch {
            assertionFailure("Failed to decode sample_courses.json: \(error)")
            return [fallbackCourse]
        }
    }

    static let fallbackCourse = Course(
        name: "ASR Golf / Los Angeles de San Rafael",
        holes: (1...18).map { number in
            Hole(
                holeNumber: number,
                greenLatitude: 40.8650 + (Double(number) * 0.00045),
                greenLongitude: -4.2385 + (Double(number) * 0.00035),
                par: [4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 4, 5, 3, 4, 4][number - 1]
            )
        }
    )
}
