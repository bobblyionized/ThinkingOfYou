//  PersonRowView.swift
//  ThinkingOfYou/UI — STUB (Core). The UI agent replaces this file.

import SwiftUI
import UIKit

struct PersonRowView: View {
    let person: Person
    var isPinned: Bool = false

    var body: some View {
        HStack {
            if let data = person.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().frame(width: 36, height: 36).clipShape(Circle())
            } else {
                Text(person.initials).frame(width: 36, height: 36).background(Circle().fill(.quaternary))
            }
            Text(person.displayName)
            if isPinned { Image(systemName: "pin.fill") }
        }
    }
}
