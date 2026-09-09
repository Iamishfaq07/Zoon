import XCTest

final class ClinicianReportRowsTests: XCTestCase {

    func testUnsetProfilePrintsNoRows() {
        XCTAssertTrue(
            ClinicianReportGenerator.demographicRows(
                age: nil, sex: .unspecified, bodyMassIndex: nil
            ).isEmpty
        )
    }

    func testSetProfilePrintsOnlyWhatWasGiven() {
        let rows = ClinicianReportGenerator.demographicRows(
            age: 41, sex: .female, bodyMassIndex: 22
        )
        XCTAssertEqual(rows.map(\.0), [
            "Age (self-reported)",
            "Sex (self-reported)",
            "BMI (self-reported)",
        ])
        XCTAssertEqual(rows.map(\.1), ["41", "Female", "22"])
    }

    func testSexAloneDoesNotInventAnAge() {
        let rows = ClinicianReportGenerator.demographicRows(
            age: nil, sex: .male, bodyMassIndex: nil
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.0, "Sex (self-reported)")
        XCTAssertEqual(rows.first?.1, "Male")
    }
}
