//
//  ImageStreamFilterView.swift
//  ImageFilters
//
//  Created by Ola Loevholm on 02/09/2025.
//

import SwiftUI

struct ImageStreamFilterView: View {
    @State private var invert = true
    
    var body: some View {
        VStack(spacing: 12) {
            FilteredCameraView(invert: $invert)
                .aspectRatio(16/9, contentMode: .fit)
                .background(.black.opacity(0.8))
                .cornerRadius(12)
            
            HStack {
                Toggle("Invert", isOn: $invert)
            }
        }
        .padding(.horizontal)
    }
}
