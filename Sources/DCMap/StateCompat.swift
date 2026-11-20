import SwiftUI

@propertyWrapper
struct StateCompat<Value>: DynamicProperty {
    private var state: State<Value>

    init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        state.projectedValue
    }
}
