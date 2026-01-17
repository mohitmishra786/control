// Control - macOS Power User Interaction Manager
// Rollback
//
// Transaction journaling for safe operations with automatic rollback.

import Foundation

// MARK: - Rollback Action

/// An action that can be rolled back
public protocol RollbackAction {
    /// Execute the action
    func execute() throws
    
    /// Undo the action (rollback)
    func rollback() throws
    
    /// Description for logging
    var description: String { get }
}

// MARK: - File Operations

/// File move action with rollback
public struct FileMoveAction: RollbackAction {
    public let source: String
    public let destination: String
    
    public var description: String {
        return "Move \(source) to \(destination)"
    }
    
    public init(from source: String, to destination: String) {
        self.source = source
        self.destination = destination
    }
    
    public func execute() throws {
        try FileManager.default.moveItem(atPath: source, toPath: destination)
    }
    
    public func rollback() throws {
        try FileManager.default.moveItem(atPath: destination, toPath: source)
    }
}

/// File copy action with rollback
public struct FileCopyAction: RollbackAction {
    public let source: String
    public let destination: String
    
    public var description: String {
        return "Copy \(source) to \(destination)"
    }
    
    public init(from source: String, to destination: String) {
        self.source = source
        self.destination = destination
    }
    
    public func execute() throws {
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }
    
    public func rollback() throws {
        try FileManager.default.removeItem(atPath: destination)
    }
}

/// File content modification with rollback
public struct FileModifyAction: RollbackAction {
    public let path: String
    public let newContent: Data
    private var originalContent: Data?
    
    public var description: String {
        return "Modify \(path)"
    }
    
    public init(path: String, newContent: Data) {
        self.path = path
        self.newContent = newContent
        self.originalContent = try? Data(contentsOf: URL(fileURLWithPath: path))
    }
    
    public func execute() throws {
        try newContent.write(to: URL(fileURLWithPath: path))
    }
    
    public func rollback() throws {
        if let original = originalContent {
            try original.write(to: URL(fileURLWithPath: path))
        } else {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}

// MARK: - Transaction

/// A transaction containing multiple actions
public final class Transaction {
    /// Transaction identifier
    public let id: UUID
    
    /// Transaction name
    public let name: String
    
    /// Actions in this transaction
    private var actions: [RollbackAction] = []
    
    /// Executed action indices (for partial rollback)
    private var executedCount: Int = 0
    
    /// Transaction state
    public private(set) var state: TransactionState = .pending
    
    public enum TransactionState: Sendable {
        case pending
        case inProgress
        case committed
        case rolledBack
        case failed
    }
    
    public init(name: String) {
        self.id = UUID()
        self.name = name
    }
    
    /// Add action to transaction
    public func add(_ action: RollbackAction) {
        guard state == .pending else { return }
        actions.append(action)
    }
    
    /// Execute all actions
    public func commit() throws {
        guard state == .pending else {
            throw TransactionError.invalidState(state)
        }
        
        state = .inProgress
        
        for (index, action) in actions.enumerated() {
            do {
                try action.execute()
                executedCount = index + 1
                log.debug("Executed: \(action.description)")
            } catch {
                log.error("Action failed: \(action.description) - \(error)")
                state = .failed
                
                // Rollback executed actions
                try rollbackExecuted()
                throw TransactionError.actionFailed(action.description, error)
            }
        }
        
        state = .committed
        log.info("Transaction committed: \(name)")
    }
    
    /// Rollback all executed actions
    public func rollback() throws {
        try rollbackExecuted()
        state = .rolledBack
        log.info("Transaction rolled back: \(name)")
    }
    
    /// Rollback only executed actions
    private func rollbackExecuted() throws {
        // Rollback in reverse order
        for index in (0..<executedCount).reversed() {
            let action = actions[index]
            do {
                try action.rollback()
                log.debug("Rolled back: \(action.description)")
            } catch {
                log.error("Rollback failed: \(action.description) - \(error)")
                // Continue rolling back other actions
            }
        }
    }
}

// MARK: - Transaction Error

public enum TransactionError: Error, LocalizedError {
    case invalidState(Transaction.TransactionState)
    case actionFailed(String, Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidState(let state):
            return "Invalid transaction state: \(state)"
        case .actionFailed(let action, let error):
            return "Action '\(action)' failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Rollback Manager

/// Manages transactions for safe operations
public final class RollbackManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = RollbackManager()
    
    // MARK: - Properties
    
    /// Active transactions
    private var transactions: [UUID: Transaction] = [:]
    private let lock = NSLock()
    
    /// Journal directory for persistence
    private let journalDir: String
    
    // MARK: - Initialization
    
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        journalDir = homeDir.appendingPathComponent(
            ".config/control/journal"
        ).path
    }
    
    // MARK: - Public Methods
    
    /// Begin a new transaction
    public func beginTransaction(name: String) -> Transaction {
        let transaction = Transaction(name: name)
        
        lock.lock()
        transactions[transaction.id] = transaction
        lock.unlock()
        
        log.info("Transaction started: \(name) (\(transaction.id))")
        return transaction
    }
    
    /// Commit a transaction
    public func commit(_ transaction: Transaction) throws {
        try transaction.commit()
        removeTransaction(transaction.id)
    }
    
    /// Rollback a transaction
    public func rollback(_ transaction: Transaction) throws {
        try transaction.rollback()
        removeTransaction(transaction.id)
    }
    
    /// Execute a block within a transaction
    public func withTransaction<T>(
        name: String,
        actions: (Transaction) throws -> T
    ) throws -> T {
        let transaction = beginTransaction(name: name)
        
        do {
            let result = try actions(transaction)
            try commit(transaction)
            return result
        } catch {
            try? rollback(transaction)
            throw error
        }
    }
    
    /// Get transaction by ID
    public func getTransaction(_ id: UUID) -> Transaction? {
        lock.lock()
        defer { lock.unlock() }
        return transactions[id]
    }
    
    // MARK: - Private Methods
    
    private func removeTransaction(_ id: UUID) {
        lock.lock()
        transactions.removeValue(forKey: id)
        lock.unlock()
    }
}
