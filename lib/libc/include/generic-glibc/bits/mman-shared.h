/* Memory-mapping-related declarations/definitions, not architecture-specific.
   Copyright (C) 2017-2025 Free Software Foundation, Inc.
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
# error "Never use <bits/mman-shared.h> directly; include <sys/mman.h> instead."
#endif

#ifdef __USE_GNU
/* Flags for mremap.  */
# define MREMAP_MAYMOVE	1
# define MREMAP_FIXED	2
# define MREMAP_DONTUNMAP 4

/* Flags for memfd_create.  */
# ifndef MFD_CLOEXEC
#  define MFD_CLOEXEC 1U
#  define MFD_ALLOW_SEALING 2U
#  define MFD_HUGETLB 4U
# endif
# ifndef MFD_NOEXEC_SEAL
#  define MFD_NOEXEC_SEAL 8U
#  define MFD_EXEC 0x10U
# endif

/* Flags for mlock2.  */
# ifndef MLOCK_ONFAULT
#  define MLOCK_ONFAULT 1U
# endif

/* Access restrictions for pkey_alloc.  */
# define PKEY_UNRESTRICTED 0x0
# define PKEY_DISABLE_ACCESS 0x1
# define PKEY_DISABLE_WRITE 0x2

__BEGIN_DECLS

// zig patch: check target glibc version
# if (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 27) || __GLIBC__ > 2

/* Create a new memory file descriptor.  NAME is a name for debugging.
   FLAGS is a combination of the MFD_* constants.  */
int memfd_create (const char *__name, unsigned int __flags) __THROW;

/* Lock pages from ADDR (inclusive) to ADDR + LENGTH (exclusive) into
   memory.  FLAGS is a combination of the MLOCK_* flags above.  */
int mlock2 (const void *__addr, size_t __length, unsigned int __flags) __THROW
    __attr_access_none (1);

#endif /* if (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 27) || __GLIBC__ > 2 */

/* Allocate a new protection key, with the PKEY_DISABLE_* bits
   specified in ACCESS_RESTRICTIONS.  The protection key mask for the
   current thread is updated to match the access privilege for the new
   key.  */
int pkey_alloc (unsigned int __flags, unsigned int __access_restrictions) __THROW;

/* Update the access restrictions for the current thread for KEY, which must
   have been allocated using pkey_alloc.  */
int pkey_set (int __key, unsigned int __access_restrictions) __THROW;

/* Return the access restrictions for the current thread for KEY, which must
   have been allocated using pkey_alloc.  */
int pkey_get (int __key) __THROW;

/* Free an allocated protection key, which must have been allocated
   using pkey_alloc.  */
int pkey_free (int __key) __THROW;

/* Apply memory protection flags for KEY to the specified address
   range.  */
int pkey_mprotect (void *__addr, size_t __len, int __prot, int __pkey) __THROW;

__END_DECLS

#endif /* __USE_GNU */
