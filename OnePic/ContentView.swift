//
//  ContentView.swift
//  OnePic
//
//  Created by Emmaa on 5/8/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        ProjectListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Photo.self], inMemory: true)
}
