// Copyright 2026 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build sparc64

package cpu

// SPARC T3 and later use a 64-byte cache line; the earlier UltraSPARC
// designs used 32. 64 is the conservative choice for padding.
const cacheLineSize = 64

func initOptions() {}
