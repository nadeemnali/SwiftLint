@testable import SwiftLintBuiltInRules
import TestHelpers
import XCTest

final class VariableShadowingRuleTests: SwiftLintTestCase {
    func testWithIgnoreParametersTrue() {
        let configuration = ["ignore_parameters": true]
        verifyRule(VariableShadowingRule.description, ruleConfiguration: configuration)
    }

    func testWithIgnoreParametersFalse() {
        let configuration = ["ignore_parameters": false]
        verifyRule(VariableShadowingRule.description, ruleConfiguration: configuration)
    }
}
