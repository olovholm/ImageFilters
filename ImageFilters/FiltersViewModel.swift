//
//  FiltersViewModel.swift
//  ImageFilters
//
//  Created by Ola Loevholm on 25/08/2025.
//

import Foundation
import SwiftUI

final class FiltersViewModel: ObservableObject {
    @Published var filters: [MetalFilter] = []
    @Published var outputImage: NSImage?

    private let engine = MetalEngine()

    init() {
        guard let engine else { return }
        do { filters = try engine.loadAvailableFilters() }
        catch { print("Failed to load filters:", error) }
    }

    func applySelected(to input: NSImage) {
        guard let engine = engine else { return }
        outputImage = engine.apply(filters: filters, to: input)
    }
}
