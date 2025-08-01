/* Definitions for POSIX memory map interface.  Linux generic version.
   Copyright (C) 2001-2025 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <https://www.gnu.org/licenses/>.  */

#ifndef _SYS_MMAN_H
# error "Never use <bits/mman-linux.h> directly; include <sys/mman.h> instead."
#endif

/* The following definitions basically come from the kernel headers.
   But the kernel header is not namespace clean.  */


/* Protections are chosen from these bits, OR'd together.  The
   implementation does not necessarily support PROT_EXEC or PROT_WRITE
   without PROT_READ.  The only guarantees are that no writing will be
   allowed without PROT_WRITE and no access will be allowed for PROT_NONE. */

#define PROT_READ	0x1		/* Page can be read.  */
#define PROT_WRITE	0x2		/* Page can be written.  */
#define PROT_EXEC	0x4		/* Page can be executed.  */
#define PROT_NONE	0x0		/* Page can not be accessed.  */
#define PROT_GROWSDOWN	0x01000000	/* Extend change to start of
					   growsdown vma (mprotect only).  */
#define PROT_GROWSUP	0x02000000	/* Extend change to start of
					   growsup vma (mprotect only).  */

/* Sharing types (must choose one and only one of these).  */
#define MAP_SHARED	0x01		/* Share changes.  */
#define MAP_PRIVATE	0x02		/* Changes are private.  */
#define MAP_SHARED_VALIDATE	0x03	/* Share changes and validate
					   extension flags.  */
#define MAP_DROPPABLE	0x08		/* Zero memory under memory pressure.  */
#define MAP_TYPE	0x0f		/* Mask for type of mapping.  */

/* Other flags.  */
#define MAP_FIXED	0x10		/* Interpret addr exactly.  */
#define MAP_FILE	0
#ifdef __MAP_ANONYMOUS
# define MAP_ANONYMOUS	__MAP_ANONYMOUS	/* Don't use a file.  */
#else
# define MAP_ANONYMOUS	0x20		/* Don't use a file.  */
#endif
#define MAP_ANON	MAP_ANONYMOUS

/* When MAP_HUGETLB is set, bits [26:31] encode the log2 of the huge page size.
   The following definitions are associated with this huge page size encoding.
   It is responsibility of the application to know which sizes are supported on
   the running system.  See mmap(2) man page for details.  */

#define MAP_HUGE_SHIFT	26
#define MAP_HUGE_MASK	0x3f

#define MAP_HUGE_16KB	(14 << MAP_HUGE_SHIFT)
#define MAP_HUGE_64KB	(16 << MAP_HUGE_SHIFT)
#define MAP_HUGE_512KB	(19 << MAP_HUGE_SHIFT)
#define MAP_HUGE_1MB	(20 << MAP_HUGE_SHIFT)
#define MAP_HUGE_2MB	(21 << MAP_HUGE_SHIFT)
#define MAP_HUGE_8MB	(23 << MAP_HUGE_SHIFT)
#define MAP_HUGE_16MB	(24 << MAP_HUGE_SHIFT)
#define MAP_HUGE_32MB	(25 << MAP_HUGE_SHIFT)
#define MAP_HUGE_256MB	(28 << MAP_HUGE_SHIFT)
#define MAP_HUGE_512MB	(29 << MAP_HUGE_SHIFT)
#define MAP_HUGE_1GB	(30 << MAP_HUGE_SHIFT)
#define MAP_HUGE_2GB	(31 << MAP_HUGE_SHIFT)
#define MAP_HUGE_16GB	(34U << MAP_HUGE_SHIFT)

/* Flags to `msync'.  */
#define MS_ASYNC	1		/* Sync memory asynchronously.  */
#define MS_SYNC		4		/* Synchronous memory sync.  */
#define MS_INVALIDATE	2		/* Invalidate the caches.  */

/* Advice to `madvise'.  */
#ifdef __USE_MISC
# define MADV_NORMAL	  0	/* No further special treatment.  */
# define MADV_RANDOM	  1	/* Expect random page references.  */
# define MADV_SEQUENTIAL  2	/* Expect sequential page references.  */
# define MADV_WILLNEED	  3	/* Will need these pages.  */
# define MADV_DONTNEED	  4	/* Don't need these pages.  */
# define MADV_FREE	  8	/* Free pages only if memory pressure.  */
# define MADV_REMOVE	  9	/* Remove these pages and resources.  */
# define MADV_DONTFORK	  10	/* Do not inherit across fork.  */
# define MADV_DOFORK	  11	/* Do inherit across fork.  */
# define MADV_MERGEABLE	  12	/* KSM may merge identical pages.  */
# define MADV_UNMERGEABLE 13	/* KSM may not merge identical pages.  */
# define MADV_HUGEPAGE	  14	/* Worth backing with hugepages.  */
# define MADV_NOHUGEPAGE  15	/* Not worth backing with hugepages.  */
# define MADV_DONTDUMP	  16    /* Explicitly exclude from the core dump,
                                   overrides the coredump filter bits.  */
# define MADV_DODUMP	  17	/* Clear the MADV_DONTDUMP flag.  */
# define MADV_WIPEONFORK  18	/* Zero memory on fork, child only.  */
# define MADV_KEEPONFORK  19	/* Undo MADV_WIPEONFORK.  */
# define MADV_COLD        20	/* Deactivate these pages.  */
# define MADV_PAGEOUT     21	/* Reclaim these pages.  */
# define MADV_POPULATE_READ 22	/* Populate (prefault) page tables
				   readable.  */
# define MADV_POPULATE_WRITE 23	/* Populate (prefault) page tables
				   writable.  */
# define MADV_DONTNEED_LOCKED 24 /* Like MADV_DONTNEED, but drop
				    locked pages too.  */
# define MADV_COLLAPSE    25	/* Synchronous hugepage collapse.  */
# define MADV_HWPOISON	  100	/* Poison a page for testing.  */
# define MADV_GUARD_INSTALL 102 /* Fatal signal on access to range */
# define MADV_GUARD_REMOVE 103  /* Unguard range */
#endif

/* The POSIX people had to invent similar names for the same things.  */
#ifdef __USE_XOPEN2K
# define POSIX_MADV_NORMAL	0 /* No further special treatment.  */
# define POSIX_MADV_RANDOM	1 /* Expect random page references.  */
# define POSIX_MADV_SEQUENTIAL	2 /* Expect sequential page references.  */
# define POSIX_MADV_WILLNEED	3 /* Will need these pages.  */
# define POSIX_MADV_DONTNEED	4 /* Don't need these pages.  */
#endif

/* Flags for `mlockall'.  */
#ifndef MCL_CURRENT
# define MCL_CURRENT	1		/* Lock all currently mapped pages.  */
# define MCL_FUTURE	2		/* Lock all additions to address
					   space.  */
# define MCL_ONFAULT	4		/* Lock all pages that are
					   faulted in.  */
#endif

#include <bits/mman-shared.h>