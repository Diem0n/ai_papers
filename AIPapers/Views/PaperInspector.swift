//
//  PaperInspector.swift
//  AIPapers
//
//  Paper detail as an inspector on the right of a full-width page, opened by
//  selecting a paper — Archive and Graph use it instead of a side list.
//

import SwiftUI

private struct PaperInspector: ViewModifier {
    @Binding var paper: Paper?
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: $shown) {
                Group {
                    if let paper {
                        PaperDetailView(paper: paper, onSelectRelated: { self.paper = $0 })
                    } else {
                        ContentUnavailableView("Select a paper", systemImage: "doc.text")
                    }
                }
                .inspectorColumnWidth(min: 380, ideal: 520, max: 760)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        shown.toggle()
                    } label: {
                        Label("Paper Detail", systemImage: "sidebar.trailing")
                    }
                    .disabled(paper == nil)
                    .help("Show or hide the selected paper's detail")
                }
            }
            .onAppear { shown = paper != nil }
            .onChange(of: paper?.id) { _, id in if id != nil { shown = true } }
    }
}

extension View {
    func paperInspector(_ paper: Binding<Paper?>) -> some View {
        modifier(PaperInspector(paper: paper))
    }
}
