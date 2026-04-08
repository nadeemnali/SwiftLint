import SwiftLintCore
import SwiftSyntax

@SwiftSyntaxRule
struct VariableShadowingRule: Rule {
    var configuration = VariableShadowingConfiguration()

    static let description = RuleDescription(
        identifier: "variable_shadowing",
        name: "Variable Shadowing",
        description: "Do not shadow variables declared in outer scopes",
        kind: .lint,
        nonTriggeringExamples: [
            Example("""
            var a: String?
            func test(a: String?) {
                print(a)
            }
            """, configuration: ["ignore_parameters": true]),
            Example("""
            var a: String = "hello"
            if let b = a {
                print(b)
            }
            """),
            Example("""
            var a: String?
            func test() {
                if let b = a {
                    print(b)
                }
            }
            """),
            Example("""
            for i in 1...10 {
                print(i)
            }
            for j in 1...10 {
                print(j)
            }
            """),
            Example("""
            func test() {
                var a: String = "hello"
                func nested() {
                    var b: String = "world"
                    print(a, b)
                }
            }
            """),
            Example("""
            class Test {
                var a: String?
                func test(a: String?) {
                    print(a)
                }
            }
            """),
            Example("""
            var outer: String = "hello"
            if let inner = Optional(outer) {
                print(inner)
            }
            """),
            Example("""
            var a: String = "outer"
            let (b, c) = ("first", "second")
            print(a, b, c)
            """),
            Example("""
            class Test {
                var property: String = "class property"
                func test() {
                    var localVar = "local"
                    print(property, localVar)
                }
            }
            """),
            Example("""
            func outer() {
                func inner() {
                    print("no shadowing")
                }
            }
            """),
            Example("""
            var result: String?
            if let unwrappedResult = result {
                print(unwrappedResult)
            }
            """),
            Example("""
            var value: Int? = 10
            guard let safeValue = value else {
                return
            }
            print(safeValue)
            """),
            Example("""
            var data: [Int?] = [1, nil, 3]
            for case let item? in data {
                print(item)
            }
            """),
        ],
        triggeringExamples: [
            Example("""
            var outer: String = "hello"
            func test() {
                let ↓outer = "world"
                print(outer)
            }
            """),
            Example("""
            var x = 1
            do {
                let ↓x = 2
                print(x)
            }
            """),
            Example("""
            var counter = 0
            func incrementCounter() {
                var ↓counter = 1
                counter += 1
            }
            """),
            Example("""
            func outer() {
                var value = 10
                do {
                    let ↓value = 20
                    print(value)
                }
            }
            """),
            Example("""
            var globalName = "global"
            func test() {
                for item in [1, 2, 3] {
                    var ↓globalName = "local"
                    print(globalName)
                }
            }
            """),
            Example("""
            var foo = 1
            do {
                let ↓foo = 2
            }
            """),
            Example("""
            var bar = 1
            func test() {
                let ↓bar = 2
            }
            """),
            Example("""
            var a = 1
            if let ↓a = Optional(2) {
                let ↓a = 3
                print(a)
            }
            """),
            Example("""
            var i = 1
            for ↓i in 1...3 {
                let ↓i = 2
                print(i)
            }
            """),
            Example("""
            func test() {
                var a = 1
                do {
                    var ↓a = 2
                    print(a)
                }
            }
            """),
            Example("""
            func test() {
                var a = 1
                if true {
                    var ↓a = 2
                    print(a)
                }
            }
            """),
            Example("""
            func test() {
                var a = 1
                for _ in 0..<1 {
                    var ↓a = 2
                    print(a)
                }
            }
            """),
            Example("""
            func test() {
                var a = 1
                while true {
                    var ↓a = 2
                    break
                }
            }
            """),
            Example("""
            var a = 1
            if let ↓a = Optional(2) {}
            """),
            Example("""
            var i = 1
            for ↓i in 1...3 {}
            """),
            Example("""
            var a: String?
            func test(↓a: String?) {
                print(a)
            }
            """, configuration: ["ignore_parameters": false]),
        ]
    )
}

private extension VariableShadowingRule {
    final class Visitor: DeclaredIdentifiersTrackingVisitor<VariableShadowingConfiguration> {
        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            if node.parent?.is(MemberBlockItemSyntax.self) == false {
                node.bindings.forEach { binding in
                    checkForShadowing(in: binding.pattern)
                }
            }
            return super.visit(node)
        }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if !configuration.ignoreParameters {
                for param in node.signature.parameterClause.parameters {
                    let nameToken = param.secondName ?? param.firstName
                    if nameToken.text != "_", isShadowingAnyScope(nameToken.text) {
                        violations.append(nameToken.positionAfterSkippingLeadingTrivia)
                    }
                }
            }
            return super.visit(node)
        }

        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
            checkForBindingShadowing(in: node.pattern)
            return super.visit(node)
        }

        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
            for condition in node.conditions {
                if let optBinding = condition.condition.as(OptionalBindingConditionSyntax.self) {
                    checkForBindingShadowing(in: optBinding.pattern)
                }
            }
            return super.visit(node)
        }

        // Used for VariableDecl: the new identifier is added to the *current* scope,
        // so we only check ancestor scopes (dropLast).
        private func checkForShadowing(in pattern: PatternSyntax) {
            if let identifier = pattern.as(IdentifierPatternSyntax.self) {
                let identifierText = identifier.identifier.text
                if isShadowingOuterScope(identifierText) {
                    violations.append(identifier.identifier.positionAfterSkippingLeadingTrivia)
                }
            } else if let tuple = pattern.as(TuplePatternSyntax.self) {
                tuple.elements.forEach { element in
                    checkForShadowing(in: element.pattern)
                }
            } else if let valueBinding = pattern.as(ValueBindingPatternSyntax.self) {
                checkForShadowing(in: valueBinding.pattern)
            }
        }

        // Used for if-let / for-loop bindings: the new identifier is added to a *child* scope,
        // so we check all current scopes.
        private func checkForBindingShadowing(in pattern: PatternSyntax) {
            if let identifier = pattern.as(IdentifierPatternSyntax.self) {
                let identifierText = identifier.identifier.text
                if isShadowingAnyScope(identifierText) {
                    violations.append(identifier.identifier.positionAfterSkippingLeadingTrivia)
                }
            } else if let tuple = pattern.as(TuplePatternSyntax.self) {
                tuple.elements.forEach { element in
                    checkForBindingShadowing(in: element.pattern)
                }
            } else if let valueBinding = pattern.as(ValueBindingPatternSyntax.self) {
                checkForBindingShadowing(in: valueBinding.pattern)
            }
        }

        private func isShadowingOuterScope(_ identifier: String) -> Bool {
            guard scope.count > 1 else { return false }

            for scopeDeclarations in scope.dropLast() where
                scopeDeclarations.contains(where: { $0.declares(id: identifier) }) {
                return true
            }
            return false
        }

        /// Checks all scope levels including the current one. Used for parameter checking
        /// since parameters are declared into a child scope, not the current one.
        private func isShadowingAnyScope(_ identifier: String) -> Bool {
            scope.contains { $0.contains { $0.declares(id: identifier) } }
        }
    }
}
