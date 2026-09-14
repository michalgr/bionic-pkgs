#pragma once

#include <sys/cdefs.h>
#include <stdint.h>

#if !defined(_BIONIC_IN_ADDR_T_DEFINED) && !defined(__in_addr_t_defined)
#define _BIONIC_IN_ADDR_T_DEFINED 1
#define __in_addr_t_defined 1
typedef uint32_t in_addr_t;
#endif

#if !defined(_STRUCT_IN_ADDR) && (!defined(__UAPI_DEF_IN_ADDR) || __UAPI_DEF_IN_ADDR == 0)
#define _STRUCT_IN_ADDR 1
#ifndef __UAPI_DEF_IN_ADDR
#define __UAPI_DEF_IN_ADDR 0
#endif
#ifndef _NETINET_IN_H
#define _NETINET_IN_H 1
#endif
struct in_addr {
  in_addr_t s_addr;
};
#endif
