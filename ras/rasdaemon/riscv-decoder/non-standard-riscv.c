// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (C) 2026 Chungbuk National University, Computer Systems Lab
 *
 * Decoder for the UEFI Processor Generic Error Section, as produced by
 * RISC-V platforms that report RERI errors through OpenSBI and GHES.
 *
 *
 * Why a *standard* section is handled by a *non-standard* decoder
 * ---------------------------------------------------------------
 * The section is standard: UEFI 2.10 N.2.4.1, GUID
 * 9876ccad-47b4-4bdb-b65e-16f193c4f3db, CPER_SEC_PROC_GENERIC in Linux.
 *
 * But ghes_do_proc() has no branch for it. It falls through to the final
 * else, which calls log_non_standard_event(), so the section arrives on
 * ras:non_standard_event with its payload untouched. rasdaemon has no
 * decoder registered for that GUID, so ras_non_standard_event_handler()
 * takes the "if (!decoded)" path and prints 192 bytes of hex.
 *
 * Registering here is the only hook that turns that hex into fields without
 * changing the kernel. The proper long-term fix is a CPER_SEC_PROC_GENERIC
 * branch in ghes_do_proc(); until then this keeps the collected records
 * readable.
 *
 *
 * Field values follow drivers/firmware/efi/cper.c so that the decoded text
 * matches what the kernel itself prints in dmesg. The RISCV entries in
 * proc_type_strs[] and proc_isa_strs[] come from the Vela kernel patch.
 */

#include <stddef.h>
#include <stdint.h>

#include "non-standard-riscv.h"
#include "ras-non-standard-handler.h"
#include "types.h"

/* The wire format is fixed by UEFI; a mismatch here means the header is wrong. */
_Static_assert(sizeof(struct riscv_proc_generic_sec) == 192,
	       "Processor Generic Error Section must be 192 bytes");

static const char * const riscv_proc_type_strs[] = {
	"IA32/X64",
	"IA64",
	"ARM",
	"RISCV",
};

static const char * const riscv_proc_isa_strs[] = {
	"IA32",
	"IA64",
	"X64",
	"ARM A32/T32",
	"ARM A64",
	"RISCV32",
	"RISCV64",
};

/* proc_error_type is a bitmask, not an index. */
static const char * const riscv_proc_error_type_strs[] = {
	"cache error",
	"TLB error",
	"bus error",
	"micro-architectural error",
};

static const char * const riscv_proc_op_strs[] = {
	"unknown or generic",
	"data read",
	"data write",
	"instruction execution",
};

/* flags is a bitmask as well. */
static const char * const riscv_proc_flag_strs[] = {
	"restartable",
	"precise IP",
	"overflow",
	"corrected",
};

static const char *str_or_unknown(const char * const *tab, size_t n, uint8_t v)
{
	return v < n ? tab[v] : "unknown";
}

static void print_bitmask(struct trace_seq *s, const char * const *tab,
			  size_t n, uint8_t val)
{
	size_t i;
	int first = 1;

	if (!val) {
		trace_seq_printf(s, " (none)");
		return;
	}

	for (i = 0; i < n; i++) {
		if (!(val & (1u << i)))
			continue;
		trace_seq_printf(s, "%s%s", first ? " (" : ", ", tab[i]);
		first = 0;
	}
	if (!first)
		trace_seq_printf(s, ")");
}

static int decode_riscv_proc_generic(struct ras_events *ras,
				     struct ras_ns_ev_decoder *ev_decoder,
				     struct trace_seq *s,
				     struct ras_non_standard_event *event)
{
	const struct riscv_proc_generic_sec *proc;
	uint64_t vb;

	if (event->length < sizeof(*proc)) {
		trace_seq_printf(s,
				 "\n  processor generic error: truncated section, got %u of %zu bytes",
				 event->length, sizeof(*proc));
		return -1;
	}

	proc = (const struct riscv_proc_generic_sec *)event->error;
	vb = proc->validation_bits;

	trace_seq_printf(s, "\n  processor generic error:");

	if (vb & RISCV_PROC_VALID_TYPE)
		trace_seq_printf(s, "\n   processor_type: %u, %s",
				 proc->proc_type,
				 str_or_unknown(riscv_proc_type_strs,
						ARRAY_SIZE(riscv_proc_type_strs),
						proc->proc_type));

	if (vb & RISCV_PROC_VALID_ISA)
		trace_seq_printf(s, "\n   processor_isa: %u, %s",
				 proc->proc_isa,
				 str_or_unknown(riscv_proc_isa_strs,
						ARRAY_SIZE(riscv_proc_isa_strs),
						proc->proc_isa));

	if (vb & RISCV_PROC_VALID_ERROR_TYPE) {
		trace_seq_printf(s, "\n   error_type: 0x%02x", proc->proc_error_type);
		print_bitmask(s, riscv_proc_error_type_strs,
			      ARRAY_SIZE(riscv_proc_error_type_strs),
			      proc->proc_error_type);
	}

	if (vb & RISCV_PROC_VALID_OPERATION)
		trace_seq_printf(s, "\n   operation: %u, %s",
				 proc->operation,
				 str_or_unknown(riscv_proc_op_strs,
						ARRAY_SIZE(riscv_proc_op_strs),
						proc->operation));

	if (vb & RISCV_PROC_VALID_FLAGS) {
		trace_seq_printf(s, "\n   flags: 0x%02x", proc->flags);
		print_bitmask(s, riscv_proc_flag_strs,
			      ARRAY_SIZE(riscv_proc_flag_strs), proc->flags);
	}

	if (vb & RISCV_PROC_VALID_LEVEL)
		trace_seq_printf(s, "\n   level: %u", proc->level);

	if (vb & RISCV_PROC_VALID_VERSION)
		trace_seq_printf(s, "\n   version_info: 0x%016llx",
				 (unsigned long long)proc->cpu_version);

	if (vb & RISCV_PROC_VALID_BRAND_INFO)
		trace_seq_printf(s, "\n   brand_info: %.128s", proc->cpu_brand);

	if (vb & RISCV_PROC_VALID_ID)
		trace_seq_printf(s, "\n   processor_id: 0x%016llx",
				 (unsigned long long)proc->proc_id);

	if (vb & RISCV_PROC_VALID_TARGET_ADDRESS)
		trace_seq_printf(s, "\n   target_address: 0x%016llx",
				 (unsigned long long)proc->target_addr);

	if (vb & RISCV_PROC_VALID_REQUESTOR_ID)
		trace_seq_printf(s, "\n   requestor_id: 0x%016llx",
				 (unsigned long long)proc->requestor_id);

	if (vb & RISCV_PROC_VALID_RESPONDER_ID)
		trace_seq_printf(s, "\n   responder_id: 0x%016llx",
				 (unsigned long long)proc->responder_id);

	if (vb & RISCV_PROC_VALID_IP)
		trace_seq_printf(s, "\n   IP: 0x%016llx",
				 (unsigned long long)proc->ip);

	/*
	 * The RERI error code is deliberately not printed: it does not reach
	 * this section. OpenSBI folds all 21 RERI codes onto the four-bit
	 * proc_error_type mask in reri_drv.c, so codes 12, 17 and 20 all
	 * arrive here as 0x08. Read status_i back from the error record if
	 * you need to know which code was injected.
	 */

	return 0;
}

/*
 * add_table is left NULL on purpose. The generic non_standard_event table
 * already stores the raw section, and adding a second table would mean
 * carrying a schema for a section whose layout UEFI already fixes.
 */
static struct ras_ns_ev_decoder riscv_ns_dec_tab[] = {
	{
		.sec_type = "9876ccad-47b4-4bdb-b65e-16f193c4f3db",
		.add_table = NULL,
		.decode = decode_riscv_proc_generic,
	},
};

static void __attribute__((constructor)) riscv_ns_init(void)
{
	size_t i;

	for (i = 0; i < ARRAY_SIZE(riscv_ns_dec_tab); i++)
		register_ns_ev_decoder(&riscv_ns_dec_tab[i]);
}
