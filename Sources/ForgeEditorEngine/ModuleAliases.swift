// Module-level aliases to resolve type name collisions.
// CoreServices.AE defines a C struct `TextRange` that conflicts with ForgeShared.TextRange.
// SwiftTreeSitter defines `Language` that conflicts with ForgeShared.Language.

import ForgeShared
import SwiftTreeSitter

// Prefer our types over system/dependency types in this module
public typealias TextRange = ForgeShared.TextRange
public typealias TextPosition = ForgeShared.TextPosition
public typealias Language = ForgeShared.Language
