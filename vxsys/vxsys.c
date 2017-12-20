/*
 * Make a bootable partition for vxworks.
 * Writen by tpu.
 *
 * Use Borland C++ 3.1 to compile it:
 * bcc -mt -lt bdisk.c
 */

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <dos.h>

#include "bt16.h"
#include "bt32.h"

typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned long  u32;


/**************************************************************/

/*

void dump(char *str, u8 *buf, int len)
{
	int i;

	if(str)
		printf("%s:", str);

	for(i=0; i<len; i++){
		if((i%16)==0)
			printf("\n%04x: ", i);
		printf(" %02x", buf[i]);
	}
	printf("\n");
}

*/

/**************************************************************/

typedef struct {
	u16 size;
	u16 count;
	u16 baddr;
	u16 bseg;
	u32 lba_l;
	u32 lba_h;
}DAP;

int bdisk_rw(int drive, long lba, char *buf, int rw)
{
	DAP dap;
	union REGS regs;
	struct SREGS sreg;

	segread(&sreg);

	dap.size = 0x10;
	dap.count = 1;
	dap.baddr = buf;
	dap.bseg = sreg.ds;
	dap.lba_l = lba;
	dap.lba_h = 0;

	regs.x.ax = (rw)? 0x4300: 0x4200;
	regs.x.si = &dap;
	regs.h.dl = drive;

	int86(0x13, &regs, &regs);

	return regs.h.ah;
}

/**************************************************************/

typedef struct {
	u8 flag;
	u8 c0;
	u8 h0;
	u8 s0;
	u8 type;
	u8 c1;
	u8 h1;
	u8 s1;
	u32 lba;
	u32 size;
}PART_ENTRY;

int find_drive(char *drive_name, int *drive_num, u32 *part_lba, int *part_type)
{
	u8 sbuf[512];
	PART_ENTRY *pt;
	int i, retv, ch, type;

	ch = drive_name[1];
	if(ch!=':' && ch!=0){
		printf("invalid Drive number!\n");
		return -1;
	}

	ch = toupper(drive_name[0]);
	if(ch>='C' && ch<='Z'){
		ch -= 'C';
	}else{
		printf("invalid Drive number!\n");
		return -1;
	}
	ch += 0x80;

	retv = bdisk_rw(ch, 0, sbuf, 0);
	if(retv){
		printf("disk read error! %02x\n", retv);
		return -1;
	}

	pt = (PART_ENTRY*)(sbuf+512-2-16*4);

	for(i=0; i<4; i++){
		type = pt[i].type;
		if(type==0x04 || type==0x06 || type==0x0b || type==0x0c || type==0x0e){
			/* Get a FAT16/FAT32 partition */
			*drive_num = ch;
			*part_lba = pt[i].lba;
			*part_type = type;
			return 0;
		}
	}

	printf("No FAT16/FAT32 found on %s!\n", drive_name);
	return -1;
}

/**************************************************************/


int main(int argc, char *argv[])
{
	u8 sbuf[512], btbuf[512];
	int i, retv, dn, type;
	u32 lba;

	printf("\nConsys VxWorks boot tool.\n");

	if(argc<2){
		printf("Usage: vxsys <drive>\n\n");
		return 0;
	}

	retv = find_drive(argv[1], &dn, &lba, &type);
	if(retv)
		return retv;
	printf("\ndrive=%02x  lba=%08lx  type=%02x FAT%d\n", dn, lba, type, (type==0x0b || type==0x0c)? 32 : 16);

	printf("Read DBR ...\n");
	retv = bdisk_rw(dn, lba, sbuf, 0);
	if(retv){
		printf("disk read error! %02x\n", retv);
		return retv;
	}

	if(type==0x0b || type==0x0c){
		// FAT32
		memcpy(btbuf, bt32, 512);
		memcpy(btbuf+0x0b, sbuf+0x0b, 0x4f);
	}else{
		// FAT16
		memcpy(btbuf, bt16, 512);
		memcpy(btbuf+0x0b, sbuf+0x0b, 0x33);
	}

	memcpy(btbuf+3, sbuf+3, 8);

	printf("Write new DBR ...\n");
	retv = bdisk_rw(dn, lba, btbuf, 1);
	if(retv){
		printf("disk write error! %02x\n", retv);
		return retv;
	}

	printf("Done.\n\n");

	return 0;
}

/**************************************************************/

