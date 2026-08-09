/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Copyright (C) 2026 Chungbuk National University, Computer Systems Lab
 */

#ifndef __NON_STANDARD_RISCV_H
#define __NON_STANDARD_RISCV_H

#include <stdint.h>

/*
 * UEFI 2.10 N.2.4.1, "Processor Generic Error Section".
 *
 * Laid out exactly as struct cper_sec_proc_generic in the Linux kernel
 * (include/linux/cper.h). Every member is naturally aligned, so the struct
 * needs no packing attribute; the static assert in the .c file checks it.
 */
struct riscv_proc_generic_sec {
	uint64_t validation_bits;
	uint8_t  proc_type;
	uint8_t  proc_isa;
	uint8_t  proc_error_type;
	uint8_t  operation;
	uint8_t  flags;
	uint8_t  level;
	uint16_t reserved;
	uint64_t cpu_version;
	char     cpu_brand[128];
	uint64_t proc_id;
	uint64_t target_addr;
	uint64_t requestor_id;
	uint64_t responder_id;
	uint64_t ip;
};

/* validation_bits, mirroring CPER_PROC_VALID_* in include/linux/cper.h */
#define RISCV_PROC_VALID_TYPE			0x0001
#define RISCV_PROC_VALID_ISA			0x0002
#define RISCV_PROC_VALID_ERROR_TYPE		0x0004
#define RISCV_PROC_VALID_OPERATION		0x0008
#define RISCV_PROC_VALID_FLAGS			0x0010
#define RISCV_PROC_VALID_LEVEL			0x0020
#define RISCV_PROC_VALID_VERSION		0x0040
#define RISCV_PROC_VALID_BRAND_INFO		0x0080
#define RISCV_PROC_VALID_ID			0x0100
#define RISCV_PROC_VALID_TARGET_ADDRESS		0x0200
#define RISCV_PROC_VALID_REQUESTOR_ID		0x0400
#define RISCV_PROC_VALID_RESPONDER_ID		0x0800
#define RISCV_PROC_VALID_IP			0x1000

#endif
