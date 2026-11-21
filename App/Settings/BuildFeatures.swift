enum BuildFeatures {
    // Manual ECG is available for validation in development builds only.
    #if DEBUG
    static let manualECG = true
    #else
    static let manualECG = false
    #endif
}
