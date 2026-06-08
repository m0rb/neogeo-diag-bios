/* Linker script for the diagnostics-as-a-cartridge (p rom) build.
 *
 * Unlike the bios build (sp1.ld, based at $c00000) this is based at $000000,
 * the cartridge p rom window, and includes room at $100 for the NEO-GEO
 * program header.  The ERR org must match ERROR_ADDRESS_BASE in sp1.inc.
 */
MEMORY {
	HEADER: org=0x000000, len=0x600
	ROM:    org=0x000600, len=0x6a00
	ERR:    org=0x007000, len=0x2000
}

SECTIONS {
	.vectors: {
		*(vectors)
	} >HEADER

	.rom: {
		*(text)
	} >ROM

	.error_addresses: {
		*(error_addresses)
	} >ERR
}
