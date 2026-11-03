// The app's sources only import Foundation, where URLSession lives in a separate module on Linux.
#if canImport(FoundationNetworking)
  @_exported import FoundationNetworking
#endif
