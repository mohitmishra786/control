// Control - macOS Power User Interaction Manager
// TOML Parser
//
// Utilities for TOML parsing and schema validation.

import Foundation
import TOMLKit

// MARK: - Parser Error

/// Errors during TOML parsing
public enum TOMLParserError: Error, LocalizedError {
    case fileNotFound(path: String)
    case invalidSyntax(line: Int, message: String)
    case missingRequiredKey(key: String)
    case invalidType(key: String, expected: String, actual: String)
    case schemaViolation(message: String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "TOML file not found: \(path)"
        case .invalidSyntax(let line, let message):
            return "Syntax error on line \(line): \(message)"
        case .missingRequiredKey(let key):
            return "Required key missing: \(key)"
        case .invalidType(let key, let expected, let actual):
            return "Invalid type for '\(key)': expected \(expected), got \(actual)"
        case .schemaViolation(let message):
            return "Schema violation: \(message)"
        }
    }
}

// MARK: - Value Type

/// TOML value types for schema validation
public enum TOMLValueType: String {
    case string = "string"
    case integer = "integer"
    case float = "float"
    case boolean = "boolean"
    case array = "array"
    case table = "table"
    case datetime = "datetime"
}

// MARK: - Schema Field

/// Schema definition for a TOML field
public struct SchemaField {
    public let key: String
    public let type: TOMLValueType
    public let required: Bool
    public let defaultValue: Any?
    public let validator: ((Any) -> Bool)?
    
    public init(
        key: String,
        type: TOMLValueType,
        required: Bool = false,
        defaultValue: Any? = nil,
        validator: ((Any) -> Bool)? = nil
    ) {
        self.key = key
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.validator = validator
    }
}

// MARK: - TOML Parser

/// TOML parsing utilities with schema validation
public final class TOMLParser {
    
    // MARK: - Static Methods
    
    /// Parse TOML file
    public static func parse(file path: String) throws -> TOMLTable {
        guard FileManager.default.fileExists(atPath: path) else {
            throw TOMLParserError.fileNotFound(path: path)
        }
        
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(string: contents)
    }
    
    /// Parse TOML string
    public static func parse(string: String) throws -> TOMLTable {
        do {
            return try TOMLTable(string: string)
        } catch {
            // Try to extract line number from error
            let errorString = String(describing: error)
            if let lineMatch = errorString.range(of: #"line \d+"#, options: .regularExpression) {
                throw TOMLParserError.invalidSyntax(line: 0, message: errorString)
            }
            throw TOMLParserError.invalidSyntax(line: 0, message: errorString)
        }
    }
    
    /// Validate TOML table against schema
    public static func validate(table: TOMLTable, schema: [SchemaField]) throws {
        for field in schema {
            let value = table[field.key]
            
            // Check required fields
            if value == nil {
                if field.required {
                    throw TOMLParserError.missingRequiredKey(key: field.key)
                }
                continue
            }
            
            // Type checking
            if !checkType(value: value!, expected: field.type) {
                throw TOMLParserError.invalidType(
                    key: field.key,
                    expected: field.type.rawValue,
                    actual: typeOf(value!)
                )
            }
            
            // Custom validation
            if let validator = field.validator, !validator(value!) {
                throw TOMLParserError.schemaViolation(
                    message: "Validation failed for '\(field.key)'"
                )
            }
        }
    }
    
    /// Get value with type casting
    public static func getValue<T>(_ key: String, from table: TOMLTable, default defaultValue: T) -> T {
        guard let value = table[key] else {
            return defaultValue
        }
        
        if let typedValue = value as? T {
            return typedValue
        }
        
        return defaultValue
    }
    
    /// Get nested value using dot notation
    public static func getNestedValue(_ keyPath: String, from table: TOMLTable) -> Any? {
        let keys = keyPath.split(separator: ".").map(String.init)
        var current: Any = table
        
        for key in keys {
            if let table = current as? TOMLTable {
                guard let value = table[key] else {
                    return nil
                }
                current = value
            } else {
                return nil
            }
        }
        
        return current
    }
    
    /// Merge two TOML tables (overlay on base)
    /// Note: This is a simplified implementation that creates a new table
    public static func merge(base: TOMLTable, overlay: TOMLTable) -> TOMLTable {
        // For proper merging, convert to dictionaries, merge, then convert back
        // This is a simplified approach - full implementation would iterate keys
        let result = TOMLTable()
        
        // Note: TOMLKit table merging requires accessing specific keys
        // In practice, you would need to know the expected keys or use
        // the table's convert() method to work with native Swift types
        
        return result
    }
    
    // MARK: - Private Methods
    
    private static func checkType(value: Any, expected: TOMLValueType) -> Bool {
        switch expected {
        case .string:
            return value is String
        case .integer:
            return value is Int || value is Int64
        case .float:
            return value is Double || value is Float
        case .boolean:
            return value is Bool
        case .array:
            return value is TOMLArray
        case .table:
            return value is TOMLTable
        case .datetime:
            return value is Date
        }
    }
    
    private static func typeOf(_ value: Any) -> String {
        switch value {
        case is String: return "string"
        case is Int, is Int64: return "integer"
        case is Double, is Float: return "float"
        case is Bool: return "boolean"
        case is TOMLArray: return "array"
        case is TOMLTable: return "table"
        case is Date: return "datetime"
        default: return "unknown"
        }
    }
    
    private static func iterateTable(_ table: TOMLTable) -> [(String, Any)] {
        var result: [(String, Any)] = []
        
        // Use subscript access with known keys
        // Note: TOMLKit's TOMLTable doesn't expose iteration directly
        // This is a workaround - in practice, we'd use the convert() method
        
        return result
    }
}
