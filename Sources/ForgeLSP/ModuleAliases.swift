import ForgeShared

// Disambiguate ForgeShared types from CoreServices.AE C types
// that leak through Foundation on macOS.
public typealias TextRange = ForgeShared.TextRange
public typealias TextPosition = ForgeShared.TextPosition
