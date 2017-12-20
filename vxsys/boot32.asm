;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                                          ;;
;;  a bootsect that load binary file to 8000. support FAT32 partition.      ;;
;;  based on "BootProg" Loader v 1.5 by Alexey Frunze                       ;;
;;                                                                          ;;
;;  nasm -f bin -o bt32.bin boot32.asm                                      ;;
;;                                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 16]

?                       equ     0
ImageLoadSeg            equ     7c14h
DATA_START              equ     7c18h
FAT_START               equ     7c1ch
FINDFILE_PTR            equ     7c20h
READCLUSTER_PTR         equ     7c22h


[SECTION .text]
[ORG 0x7c00]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Boot sector starts here ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        jmp     short   start                   ; MS-DOS/Windows checks for this jump
        nop
bsOemName               DB      "ConsysVX"      ; 0x03

;;;;;;;;;;;;;;;;;;;;;
;; BPB starts here ;;
;;;;;;;;;;;;;;;;;;;;;

bpbBytesPerSector       DW      ?               ; 0x0B   *  512
bpbSectorsPerCluster    DB      ?               ; 0x0D   *
bpbReservedSectors      DW      ?               ; 0x0E   *
bpbNumberOfFATs         DB      ?               ; 0x10   *  2
bpbRootEntries          DW      ?               ; 0x11
bpbTotalSectors         DW      ?               ; 0x13
bpbMedia                DB      ?               ; 0x15
bpbSectorsPerFAT        DW      ?               ; 0x16
bpbSectorsPerTrack      DW      ?               ; 0x18
bpbHeadsPerCylinder     DW      ?               ; 0x1A
bpbHiddenSectors        DD      ?               ; 0x1C   *
bpbTotalSectorsBig      DD      ?               ; 0x20

;;;;;;;;;;;;;;;;;;;
;; BPB ends here ;;
;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;
;; BPB2 starts here ;;
;;;;;;;;;;;;;;;;;;;;;;

bsSectorsPerFAT32               DD      ?               ; 0x24   *
bsExtendedFlags                 DW      ?               ; 0x28
bsFSVersion                     DW      ?               ; 0x2A
bsRootDirectoryClusterNo        DD      ?               ; 0x2C   *
bsFSInfoSectorNo                DW      ?               ; 0x30
bsBackupBootSectorNo            DW      ?               ; 0x32
bsreserved             times 12 DB      ?               ; 0x34
bsDriveNumber                   DB      ?               ; 0x40   *
bsreserved1                     DB      ?               ; 0x41
bsExtendedBootSignature         DB      ?               ; 0x42
bsVolumeSerialNumber            DD      ?               ; 0x43
bsVolumeLabel          times 11 DB      ?               ; 0x47   "NO NAME    "   
bsFileSystemName       times 8  DB      90h             ; 0x52   "FAT32   "

;;;;;;;;;;;;;;;;;;;;
;; BPB2 ends here ;;
;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Boot sector code starts here ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

start:
        push    cs
        pop     ds
        mov     [bsDriveNumber], dl     ; store BIOS boot drive number

        mov     si, Logo
        call    puts

        mov     ax, 0800h
        mov     [ImageLoadSeg], ax
        mov     ax, FindFile
        mov     [FINDFILE_PTR], ax
        mov     ax, ReadCluster
        mov     [READCLUSTER_PTR], ax

        movzx   eax, word [bpbReservedSectors]
        add     eax, [bpbHiddenSectors]
        mov     [FAT_START], eax

        movzx   eax, byte [bpbNumberOfFATs]
        mul     dword [bsSectorsPerFAT32]
        add     eax, [FAT_START]
        mov     [DATA_START], eax

        call    FindFile

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Load the entire file ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

        push    word [ImageLoadSeg]
        pop     es
        xor     bx, bx
FileReadContinue:
        call    ReadCluster             ; read one cluster of root dir
        jnc     FileReadDone
        pushad
        mov     ax, 0x0e2e
        mov     bx, 7
        int     10h
        popad
        jmp     short FileReadContinue

FileReadDone:
        mov     si, FileLoadDone
        call    puts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; All done, transfer control to the program now ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        push    word [ImageLoadSeg]
        push    word 0
        retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Find file in root directory            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Input:  file name at  0x7df3           ;;
;;         temp buff at [0x7c14]          ;;
;; Output: esi = first cluster            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

FindFile:

        mov     esi, [bsRootDirectoryClusterNo] ; esi=cluster # of root dir
RootDirReadContinue:
        push    word [ImageLoadSeg]
        pop     es
        xor     bx, bx                  ; es:bx -> buffer for root directory
        call    ReadCluster             ; read one cluster of root dir
        mov     ebp, esi                ; save esi=next cluster # of root dir
        setc    bl                      ; save carry="not last cluster" flag to bl

        push    word [ImageLoadSeg]
        pop     es
        xor     di, di                  ; es:di -> root entries array
        mov     si, ProgramName         ; ds:si -> program name
        movzx   dx, [bpbSectorsPerCluster]
        shl     dx, 4                   ; 16: dir entries per sector (512/32)
        mov     cx, 11

FindNameCycle:
        cmp     byte [es:di], ch
        je      ErrFind                 ; end of root directory (NULL entry found)
        pusha
        repe    cmpsb
        popa
        je      FindNameFound
        add     di, 32
        dec     dx
        jnz     FindNameCycle           ; next root entry
        mov     esi, ebp                ; restore esi=next cluster # of root dir
        test    bl, 1
        jnz     RootDirReadContinue     ; continue to the next root dir cluster
ErrFind:
        mov     si, FileNotFound
        call    puts
        jmp     short $

FindNameFound:
        push    word [es:di+14h]
        push    word [es:di+1Ah]
        pop     esi                     ; si = cluster no.
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reads a FAT32 cluster        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Inout:  ES:BX -> buffer      ;;
;;            ESI = cluster no  ;;
;; Output:    ESI = next cluster;;
;;         ES:BX -> next addr   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ReadCluster:
        mov     eax, esi
        shr     eax, 7
        add     eax, [FAT_START]
        mov     cx, 1
        call    ReadSectorLBA           ; read 1 FAT32 sector

        lea     eax, [esi-2]
        movzx   ecx, byte [bpbSectorsPerCluster]
        mul     ecx
        add     eax, [DATA_START]       ; eax: sector of DATA

        and     esi, 07fh               ; cluster offset in sector
        mov     esi, [es:esi*4]         ; si=next cluster #

        call    ReadSectorLBA

        shl     cx, 5
        mov     ax, es
        add     ax, cx
        mov     es, ax                  ; es:bx updated

        cmp     esi, 0FFFFFF8h          ; carry=0 if last cluster, and carry=1 otherwise
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reads a sector using BIOS Int 13h fn 42h ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Input:  EAX    = LBA                     ;;
;;         CX     = sector count            ;;
;;         ES:BX -> buffer address          ;;
;; Output: CF = 1 if error                  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ReadSectorLBA:
        pushad

        push    byte 0
        push    byte 0  ; 32-bit LBA only: up to 2TB disks
        push    eax
        push    es
        push    bx
        push    cx      ; sector count
        push    byte 16 ; packet size byte = 16, reserved byte = 0

        mov     ah, 42h
        mov     dl, [bsDriveNumber]
        mov     si, sp
        push    ss
        pop     ds
        int     13h
        push    cs
        pop     ds

        jc      short ErrRead
        add     sp, 16 ; the two instructions are swapped so as not to overwrite carry flag
        popad
        ret

ErrRead:
        mov     si, DiskReadError
        call    puts
        jmp     short $

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Messaging Print Code ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

puts:
.loop:
        lodsb
        or      al, al
        jz      .exit
        mov     ah, 0eh
        mov     bx, 7
        int     10h
        jmp     .loop
.exit:
        ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Strings                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Logo            db      "Consys VXLD 2.0", 0dh, 0ah, 0
FileNotFound    db      "File Not Found", 0
FileLoadDone    db      0dh, 0ah, "File Load Done", 0
DiskReadError   db      0dh, 0ah, "Disk Read Error", 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Fill free space with zeroes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

times (512-13-($-$$)) db 0

ProgramName     db      "BOOTROM SYS"   ; name and extension each must be padded with spaces (11 bytes total)

;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of the sector ID ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

                dw      0AA55h          ; BIOS checks for this ID

