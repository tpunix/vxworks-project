;
; vxld - load and boot vxworks image directly from dos
;
; nasm -f bin -o vxld.com vxld.asm
;

data_buf	equ 0x7000

[section .text]
align 4
org 0x0100

	lea		dx, [prg_msg]
	call	show_str

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; turn on A20                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

a20_on:
.L1:
	in		al, 0x64
	test	al, 2
	jnz		.L1
	mov		al, 0xd1
	out		0x64, al
.L2:
	in		al, 0x64
	test	al, 2
	jnz		.L2
	mov		al, 0xdf
	out		0x60, al
.L3:
	in		al, 0x64
	test	al, 2
	jnz		.L3
	mov		al, 0xff
	out		0x64, al

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Enter protect mode, exit with back-door                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pmode_set0:
	mov		ebx, ds
	shl		ebx, 4
	mov		eax, vx_gdt
	add		eax, ebx
	mov		[vx_gdtr+2], eax
	lgdt	[vx_gdtr]
	cli
	mov		bx, 0x10
	mov		eax, cr0
	or		al, 1
	mov		cr0, eax
	jmp		.Lpmode
	nop

.Lpmode:
	mov		ds, bx
	mov		es, bx
	and		al, 0xfe
	mov		cr0, eax
	jmp		.Lrmode
	nop

.Lrmode:
	mov		ax, cs
	mov		ds, ax
	mov		es, ax
	sti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Open binary file                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

open_file:

	mov		si, 0x0081
	mov		di, fname
.L_skip_space:
	lodsb
	cmp		al, 0x20
	jz		.L_skip_space
.L_copy:
	cmp		al, 0x0d
	jz		.L_copy_done
	cmp		al, 0x20
	jz		.L_copy_done
	stosb
	mov		byte[di], 0
	lodsb
	jmp		.L_copy
.L_copy_done:

	mov		ax, 0x3d00
	mov		dx, fname
	int		0x21
	jnc		.L_open_ok
.L_open_faile:
	mov		dx, open_msg1
	call	show_str
	int		0x20

.L_open_ok:
	mov		[vx_fd], ax

	mov		bx, ax
	mov		ax, 0x4202
	mov		dx, 0
	mov		cx, dx
	int		0x21

	mov		[fsize+0], ax
	mov		[fsize+2], dx

	mov		bx, [vx_fd]
	mov		ax, 0x4200
	mov		dx, 0
	mov		cx, dx
	int		0x21

	mov		dx, open_msg2
	call	show_str
	mov		eax, [fsize]
	call	show_eax
	call	show_return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read binary file                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

read_file:
	mov		eax, 0x00408000
	mov		[dst_addr], eax

.L_read_loop:
	mov		ah, 0x3f
	mov		bx, [vx_fd]
	mov		cx, 0x8000
	mov		dx, data_buf
	int		0x21
	jnc		.L_copy_data
	mov		dx, read_msg1
	call	show_str
	int		0x20

.L_copy_data:
	mov		[read_len], ax
	movzx	ecx, ax
	push	es
	xor		ax, ax
	mov		es, ax
	mov		esi, data_buf,
	mov		edi, [dst_addr]
	db		0x67
	rep		movsb
	pop		es
	mov		[dst_addr], edi

	mov		dl, '.'
	call	show_ch

	mov		ax, [read_len]
	cmp		ax, 0x8000
	jz		.L_read_loop

	mov		ah, 0x3e
	mov		bx, [vx_fd]
	int		0x21

	call	show_return
	mov		dx, read_msg2
	call	show_str


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Enter protect mode, jump to vxworks                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pmode_set1:
	lidt	[vx_idtr]
	lgdt	[vx_gdtr]
	cli
	mov		bx, 0x10
	mov		eax, cr0
	or		al, 1
	mov		cr0, eax
	jmp		.L_pmode
	nop

.L_pmode:
	mov		ds, bx
	mov		es, bx
	mov		fs, bx
	mov		gs, bx
	mov		ss, bx

	jmp		dword 0x0008:0x00408000
	nop


prg_msg		db "Consys vxload tools.", 0x0d, 0x0a, '$'
open_msg1	db "Open file failed", 0x0d, 0x0a, '$'
open_msg2	db "File size: ", '$'
read_msg1	db "Read file failed", 0x0d, 0x0a, '$'
read_msg2	db "Read file done", 0x0d, 0x0a, '$'

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_eax:
	rol		eax, 16
	call	show_ax
	rol		eax, 16
show_ax:
	rol		ax, 8 
	call	show_al
	rol		ax, 8
show_al:
	rol		al, 4 
	call	show_aln
	rol		al,	4
show_aln:
	push	ax  
	push	dx
	mov		dl, al
	and		dl, 0x0f
	cmp		dl, 0x0a
	jb		.L1
	add		dl, 7
.L1:
	add		dl, 0x30
	call	show_ch
	pop dx
	pop ax
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_ch:
	push	ax
	push	bx
	mov		al, dl
	mov		ah, 0x0e
	mov		bl, 0x07
	int		0x10
	pop		bx
	pop		ax
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_return:
	push	dx  
	mov		dl, 0x0d
	call	show_ch
	mov		dl, 0x0a
	call	show_ch
	pop		dx
	ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_space:
	push	dx  
	mov		dl, 0x20
	call	show_ch
	pop		dx
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

show_str:
	push	ax  
	mov		ah, 0x09
	int		0x21
	pop		ax
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

vx_idtr		dw 0x0000
			dd 0x00000000

vx_gdtr		dw 0x0027
			dd 0x00000000

			;; sel 0: NULL desc
vx_gdt		dw 0x0000
			dw 0x0000
			db 0x00, 0x00, 0x00, 0x00
			;; sel 1: CODE desc
			dw 0xffff
			dw 0x0000
			db 0x00, 0x9a, 0xcf, 0x00
			;; sel 2: DATA desc
			dw 0xffff
			dw 0x0000
			db 0x00, 0x92, 0xcf, 0x00
			;; sel 3: CODE desc, for nesting interrupt
			dw 0xffff
			dw 0x0000
			db 0x00, 0x9a, 0xcf, 0x00
			;; sel 4: CODE desc, for nesting interrupt
			dw 0xffff
			dw 0x0000
			db 0x00, 0x9a, 0xcf, 0x00

read_len	dw 0
vx_fd		dw 0
fsize		dd 0
dst_addr	dd 0

fname		times 32 db 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

