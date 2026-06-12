// Test helper: send a media command to whatever the *system* considers the
// current Now Playing app, via the private MediaRemote framework. Used to
// verify end-to-end that sound-keko owns the media keys and forwards to ncspot.
//
//   swiftc -o /tmp/mrsend scripts/send-system-mediakey.swift
//   /tmp/mrsend 2   # 0=play 1=pause 2=togglePlayPause 4=next 5=previous
import Foundation

let handle = dlopen(
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)!
typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
let send = unsafeBitCast(dlsym(handle, "MRMediaRemoteSendCommand")!, to: SendCommandFn.self)

let command = Int32(CommandLine.arguments.dropFirst().first.flatMap { Int($0) } ?? 2)
let ok = send(command, nil)
print("MRMediaRemoteSendCommand(\(command)) -> \(ok)")
