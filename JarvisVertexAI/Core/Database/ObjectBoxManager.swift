//
//  ObjectBoxManager.swift
//  JarvisVertexAI
//
//  Privacy-First Local Database with AES-256 Encryption
//  100% On-Device Storage - No Cloud Sync
//

// This file is disabled to avoid ObjectBox compilation issues
// Use SimpleDataManager instead (via typealias at bottom)

/*
// All ObjectBox implementation is commented out to avoid compilation issues
// See SimpleDataManager.swift for the current implementation
*/

import Foundation

// MARK: - ObjectBoxManager Typealias
// This redirects all ObjectBoxManager calls to SimpleDataManager
typealias ObjectBoxManager = SimpleDataManager