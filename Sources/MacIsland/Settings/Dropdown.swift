import SwiftUI

// The Settings window's dropdowns: a rounded field that opens a list in a popover, instead of the system pop-up button. One look
// for every choice, and a list can hold more than choices (headings, a remove button on a row). `SettingsDropdown` is a
// `Picker` for a Form row; `StyledDropdown` with `DropdownItem`s is for anything else.

/// Closes the dropdown a row is in.
private struct DropdownDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var dropdownDismiss: () -> Void {
        get { self[DropdownDismissKey.self] }
        set { self[DropdownDismissKey.self] = newValue }
    }
}

/// The field: a label and a chevron on a soft rounded fill. Clicking it opens `content` in a popover.
struct StyledDropdown<Label: View, Content: View>: View {
    /// What VoiceOver calls the field.
    let accessibilityLabel: String
    /// False for a field that is only an icon.
    var showsChevron = true
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    @State private var isOpen = false
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                label
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(Color.primary.opacity(isOpen ? 0.16 : (isHovering ? 0.12 : 0.07)), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            // A long list scrolls instead of running off the screen.
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
            }
            .frame(maxHeight: 320)
            .environment(\.dropdownDismiss) { isOpen = false }
        }
        .fixedSize()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .padding(6)
            .frame(minWidth: 190, alignment: .leading)
    }
}

/// One row in a dropdown: a check when it is the current choice, an optional symbol, and the title. Choosing it runs `action` and closes
/// the dropdown. `trailing` is a control of its own at the end of the row (a remove button).
struct DropdownItem<Trailing: View>: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var isDestructive = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    @Environment(\.dropdownDismiss) private var dismiss
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                // Closed first, so a panel or an alert the action opens isn't fighting the popover for the window.
                dismiss()
                DispatchQueue.main.async(execute: action)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                    if let systemImage {
                        Image(systemName: systemImage)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                }
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
                .padding(.leading, 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            trailing
        }
        .frame(height: 28)
        .background(
            isHovering ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isHovering = $0 }
    }
}

extension DropdownItem where Trailing == EmptyView {
    init(
        title: String, systemImage: String? = nil, isSelected: Bool = false, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, systemImage: systemImage, isSelected: isSelected, isDestructive: isDestructive,
            action: action
        ) { EmptyView() }
    }
}

/// A small heading between groups of rows.
struct DropdownHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A line between groups of rows.
struct DropdownDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}

/// A value to choose, and what it is called.
struct DropdownOption<Value: Hashable> {
    let value: Value
    let title: String

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }

    /// One option for each value, titled by `title`.
    static func all(_ values: [Value], title: (Value) -> String) -> [DropdownOption<Value>] {
        values.map { DropdownOption($0, title($0)) }
    }
}

/// A `Picker` for a Form row in the styled dropdown: the title on the left and the field on the right.
struct SettingsDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [DropdownOption<Value>]

    var body: some View {
        LabeledContent(title) {
            StyledDropdown(accessibilityLabel: title) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    DropdownItem(title: option.title, isSelected: option.value == selection) {
                        selection = option.value
                    }
                }
            } label: {
                Text(options.first { $0.value == selection }?.title ?? "")
            }
        }
        .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
    }
}

/// A button in the dropdown's look: a rounded field with a title and a symbol.
struct FieldButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(Color.primary.opacity(isHovering ? 0.12 : 0.07), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .fixedSize()
    }
}

/// A row of mutually exclusive choices in the dropdown's look, each one a button: clicking a name picks it. A choice can be dimmed
/// and unavailable (a size that won't fit).
struct SettingsSegmented<Value: Hashable>: View {
    let options: [DropdownOption<Value>]
    @Binding var selection: Value
    /// Whether a choice can be picked; a dimmed one says why in its help.
    var isEnabled: (Value) -> Bool = { _ in true }
    var accessibilityLabel: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                SegmentButton(
                    title: option.title, isSelected: option.value == selection, isEnabled: isEnabled(option.value)
                ) {
                    selection = option.value
                }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: shape)
        // The border is drawn over the buttons, so it must not take their clicks.
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 22)
                .background(
                    isSelected
                        ? Color.accentColor : (isHovering && isEnabled ? Color.primary.opacity(0.1) : Color.clear),
                    in: shape
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
