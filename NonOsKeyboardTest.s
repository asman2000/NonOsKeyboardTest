;
;Non Os Keyboard Test
;
;=============================================================================

	IFD BARFLY

	OUTPUT	"RAM:nokt"
	BOPT	O+		;enable optimizing
	BOPT	OG+		;enable optimizing
	BOPT	ODd-		;disable mul optimizing
	BOPT	ODe-		;disable mul optimizing
	BOPT	w4-		;disable 64k warnings
	BOPT	wo+		;enable optimize warnings
	SUPER

	ENDC	;END IFD BARFLY

;=============================================================================

	INCDIR	"includes:"
	INCLUDE	"hardware/cia.i"
	INCLUDE	"hardware/custom.i"
	INCLUDE	"hardware/dmabits.i"
	INCLUDE	"hardware/intbits.i"

_custom		equ	$dff000
_ciaa		equ	$bfe001

SCREEN_BPL	= 4
SCREEN_BROW	= 40		;bytes per row
SCREEN_WIDTH	= 320
SCREEN_HEIGHT	= 256		;height of bitplan

SCREEN_LINE	= SCREEN_BROW*SCREEN_BPL
SCREEN_MODULO	= (SCREEN_BPL-1)*SCREEN_BROW

SCREEN_SIZE	= SCREEN_BROW*SCREEN_HEIGHT*SCREEN_BPL
COPPER_SIZE	= 512

WAIT_BEAM:	MACRO
		lea	vposr(a5),a0
.1\@		moveq	#1,d0
		and.w	(a0),d0
		bne.b	.1\@
.2\@		moveq	#1,d0
		and.w	(a0),d0
		beq.b	.2\@
	ENDM

;-----------------------------------------------------------------------------
	RSRESET
screen:			rs.l	1
copper:			rs.l	1
spriteFake:		rs.l	1
oldStack:		rs.l	1
oldView:		rs.l	1
oldIntena:		rs.w	1	;\ do not split
oldDma:			rs.w	1	;/
vbrBase:		rs.l	1
oldIntPorts:		rs.l	1
gfxBase:		rs.l	1
dosBase:		rs.l	1

keys:			rs.b	$80

	;adjust to long word !!!
variables_SIZEOF:	rs.b	0

;-----------------------------------------------------------------------------

program:
		bsr.w	DoVariables
		bsr.w	OpenLibsAndGetVbr
		tst.l	d0
		beq.s	Exit
		bsr.w	DisableOs
		bsr.w	Main
ExitToOs:	bsr	EnableOs
Exit		bsr	CloseGraphicsLib
		move.l	dt+oldStack(pc),a7
		rts

;-----------------------------------------------------------------------------
;
;out
;a6	dt
;
DoVariables:
		lea	dt(pc),a6

	;clear dt
		move.l	a6,a0
		moveq	#0,d0
		move.w	#variables_SIZEOF/4-1,d1
.clear		move.l	d0,(a0)+
		dbf	d1,.clear

	;set chip pointer offsets
		lea	chipScreen,a0
		move.l	a0,screen(a6)
		lea	chipCopper,a0
		move.l	a0,copper(a6)
		lea	chipSpriteFake,a0
		move.l	a0,spriteFake(a6)

	;store old stack pointer
		lea	4(a7),a0
		move.l	a0,oldStack(a6)

		rts

;-----------------------------------------------------------------------------
;in
;a6	dt
;
;out
;a5	custom
;
DisableOs:
		move.l	a6,a4

	;save old view
		move.l	gfxBase(a4),a6
		move.l  $22(a6),oldView(a4)

	;reset display
		sub.l	a1,a1
		bsr.b	ResetDisplay

	;store hardware registers
		lea	_custom,a5
		move.w	intenar(a5),oldIntena(a4)
		move.w	dmaconr(a5),oldDma(a4)
		or.l	#$c0008000,oldIntena(a4)

	;store ints (PORTS)
		move.w	#$7fff,intena(a5)
		move.w	#$7fff,intreq(a5)
		move.w	#$7fff,dmacon(a5)
		move.w	#INTF_PORTS,intena(a5)
		move.w	#INTF_PORTS,intreq(a5)
		move.l	vbrBase(a4),a0
		move.l	$68(a0),oldIntPorts(a4)

		move.l	a4,a6
		rts

;-----------------------------------------------------------------------------
;in
;a5	custom
;a6	dt
;
EnableOs:
		move.l	a6,a4

	;restore ints pointers (PORTS)
		move.w	#INTF_PORTS,intena(a5)	;disable PORTS int
		move.w	#INTF_PORTS,intreq(a5)	;clear pending PORTS int
		move.l	vbrBase(a4),a0
		move.l	oldIntPorts(a4),$68(a0)

	;restore hardware regs
		move.w	oldIntena(a4),intena(a5)
		move.w	oldDma(a4),dmacon(a5)

	;load old view
		move.l	oldView(a4),a1
		move.l	gfxBase(a4),a6
		bsr.b	ResetDisplay
		move.l	$26(a6),cop1lc(a5)	;restore system clist .gb_copinit

		move.l	a4,a6
		rts

;-----------------------------------------------------------------------------
;in
;	a6 - gfx base
;	a1 - view
ResetDisplay:
		jsr	-222(a6)	;gfx LoadView
		jsr	-270(a6)	;gfx WaitTOF
		jmp	-270(a6)	;gfx WaitTOF

;-----------------------------------------------------------------------------
;
;in
;a6	dt
;
;out
;d0	zero mean some library do not open 
;	non zero everything were ok
;
OpenLibsAndGetVbr:

		move.l	a6,a4
	;get vbr
		move.l	4.w,a6
		moveq	#0,d1
		btst.b	#0,$129(a6)	;test bit AFB_68010 on AttnFlags+1
		beq.s	.mc68000

		lea	.getvbr(pc),a5
		jsr	-30(a6)		;exec Supervisor

.mc68000	move.l	d1,vbrBase(a4)

		lea	.gfxName(pc),a1
		jsr	-408(a6)
		move.l	d0,gfxBase(a4)
		beq.w	.exit

.exit		move.l	a4,a6
		rts

.gfxName:	dc.b	'graphics.library',0,0

.getvbr		dc.w	$4e7a,$1801	;movec	vbr,d1
		rte

;-----------------------------------------------------------------------------
;
;in
;a6	dt
;
;out
;a6	exec base
;
CloseGraphicsLib:
		move.l	gfxBase(a6),a1		;lib base
		move.l	4.w,a6			;exec base
		tst.l	(a1)
		beq.b	.exit
		jsr	-414(a6)		;exec CloseLibrary
.exit		rts

;-----------------------------------------------------------------------------
Main:
		bsr	Init

		move.l	screen(a6),a1
		add.l	#SCREEN_LINE*240,a1
		lea	pubInfoText(pc),a0
		bsr	FontStringDraw
Loop:
		WAIT_BEAM

	;clear block 12x240 
		move.l	screen(a6),a0
		moveq	#0,d0
		moveq	#120-1,d1
		move.l	#SCREEN_LINE-12,d2
.clear
		move.l	d0,(a0)+
		move.l	d0,(a0)+
		move.l	d0,(a0)+
		add.l	d2,a0
		move.l	d0,(a0)+
		move.l	d0,(a0)+
		move.l	d0,(a0)+
		add.l	d2,a0
		dbf	d1,.clear

	;test keycodes
		move.l	screen(a6),d2
		lea	pubKeyCodes(pc),a0
		move.l	a0,d3
		moveq	#128-1,d1		;amount of keycodes
		lea	keys(a6),a4
		move.l	#SCREEN_LINE*8,d4
		moveq	#11,d5
.loop		tst.b	(a4)+
		beq.b	.next

		move.l	d3,a0
		move.l	d2,a1
		add.l	d4,d2
		bsr	FontStringDraw

.next		add.l	d5,d3
		dbf	d1,.loop

.checkLeftMouseButton
		btst	#6,$bfe001
		bne.b	Loop

		rts

;-----------------------------------------------------------------------------
;a0 - string
;a1 - screen
FontStringDraw:
		lea	pubFonts(pc),a2

.loop		moveq	#0,d0
		move.b	(a0)+,d0
		beq	.exit
		lsl.w	#3,d0
		move.l	a2,a3
		add.l	d0,a3

		move.b	(a3)+,(a1)
		move.b	(a3)+,SCREEN_LINE*1(a1)
		move.b	(a3)+,SCREEN_LINE*2(a1)
		move.b	(a3)+,SCREEN_LINE*3(a1)
		move.b	(a3)+,SCREEN_LINE*4(a1)
		move.b	(a3)+,SCREEN_LINE*5(a1)
		move.b	(a3)+,SCREEN_LINE*6(a1)
		move.b	(a3)+,SCREEN_LINE*7(a1)

		addq.l	#1,a1
		bra	.loop

.exit		rts

;-----------------------------------------------------------------------------

IntLvlTwoPorts:
		movem.l	d0-d1/a0-a2,-(a7)

		lea	_custom,a0
		moveq	#INTF_PORTS,d0

	;check if is it level 2 interrupt
		move.w	intreqr(a0),d1
		and.w	d0,d1
		beq.b	.end

	;check if SP cause interrupt, hopefully CIAICRF_SP = 8
		lea	_ciaa,a1 
		move.b	ciaicr(a1),d1
		and.b	d0,d1
		beq.b	.end

		move.b	ciasdr(a1),d1			;get keycode
		or.b	#CIACRAF_SPMODE,ciacra(a1)	;start SP handshaking

		lea	dt+keys(pc),a2
		not.b	d1
		lsr.b	#1,d1
		scc	(a2,d1.w)

	;handshake
		moveq	#3-1,d1
.wait1		move.b	vhposr(a0),d0
.wait2		cmp.b	vhposr(a0),d0
		beq.b	.wait2
		dbf	d1,.wait1

	;set input mode
		and.b	#~(CIACRAF_SPMODE),ciacra(a1)

.end		move.w	#INTF_PORTS,intreq(a0)
		tst.w	intreqr(a0)
		movem.l	(a7)+,d0-d1/a0-a2
		rte

;-----------------------------------------------------------------------------
; in
;a5 - custom
; out
;a6 - dt variables
;
Init:
	;set up PORTS int

	;clear ports interrupt
		move.w	#INTF_PORTS,intreq(a5)

		lea	IntLvlTwoPorts(pc),a0
		move.l	vbrBase(a6),a1
		move.l	a0,$68(a1) 

	;allow ports interrupt
		move.w	#INTF_SETCLR|INTF_INTEN|INTF_PORTS,intena(a5)

	;set screen hardware registers
		lea	pubScreenRegs(pc),a0
		moveq	#(pubScreenRegsEnd-pubScreenRegs)/4-1,d0
.setScreenRegs
		move.w	(a0)+,d1
		move.w	(a0)+,(a5,d1.w)
		dbf	d0,.setScreenRegs

		bsr	DoCopperList

	;set screen 
		move.l	copper(a6),cop1lc(a5)
		WAIT_BEAM
		move.w	#DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER,dmacon(a5)

		rts

;-----------------------------------------------------------------------------
;in
;	a0 - copper
;	d0 - screen
;	a6 - dt
;out
;
DoCopperList:

	;set bitplanes
		move.l	copper(a6),a0
		moveq	#2,d1
		move.w	#bplpt,d2
		swap	d1
		move.l	screen(a6),d0
		moveq	#SCREEN_BPL-1,d3
		moveq	#SCREEN_BROW,d4
		bsr	.copperSetPointers

	;set sprites
		move.w	#sprpt,d2
		moveq	#8-1,d3
		move.l	spriteFake(a6),d0
		moveq	#0,d4
		bsr	.copperSetPointers

	;add end copperlist
		moveq	#-2,d0
		move.l	d0,(a0)+

		rts

;
;in	a0 - copper
;	d0 - screen or sprite
;	d1 - $02000000
;	d2 - bplpt or sprpt
;	d3 - amount of  bpl - 1  or  spr - 1
;	d4 - next bpl or spr
;
.copperSetPointers:
		swap	d2

.loop		swap	d0
		move.w	d0,d2
		move.l	d2,(a0)+
		add.l	d1,d2
		swap	d0
		move.w	d0,d2
		move.l	d2,(a0)+
		add.l	d1,d2
		add.l	d4,d0
		dbf	d3,.loop
		rts

;-----------------------------------------------------------------------------

dt:	ds.b	variables_SIZEOF

pubScreenRegs:
		dc.w	color,0
		dc.w	color+2,$888
		dc.w	diwstrt,$2c81
		dc.w	diwstop,$2cc1
		dc.w	ddfstrt,$0038
		dc.w	ddfstop,$00d0  
		dc.w	bplcon0,SCREEN_BPL*$1000+$200
		dc.w	bplcon1,0
		dc.w	bplcon2,0
		dc.w	bpl1mod,SCREEN_MODULO
		dc.w	bpl2mod,SCREEN_MODULO
pubScreenRegsEnd:

pubInfoText:	dc.b	'Non Os Keyboard Test v1.0. LMB to exit.',0

	EVEN

pubKeyCodes:
			;1234567890	;11 bytes to next
		dc.b	"`         ",0	;0
		dc.b	"1         ",0	;1
		dc.b	"2         ",0	;2
		dc.b	"3         ",0	;3
		dc.b	"4         ",0	;4
		dc.b	"5         ",0	;5
		dc.b	"6         ",0	;6
		dc.b	"7         ",0	;7
		dc.b	"8         ",0	;8
		dc.b	"9         ",0	;9
		dc.b	"0         ",0	;a
		dc.b	"-         ",0	;b
		dc.b	"=         ",0	;c
		dc.b	"\         ",0	;d
		dc.b	"$0e       ",0	;e
		dc.b	"num 0     ",0	;f
		dc.b	"q         ",0	;10
		dc.b	"w         ",0	;11
		dc.b	"e         ",0	;12
		dc.b	"r         ",0	;13
		dc.b	"t         ",0	;14
		dc.b	"y         ",0	;15
		dc.b	"u         ",0	;16
		dc.b	"i         ",0	;17
		dc.b	"o         ",0	;18
		dc.b	"p         ",0	;19
		dc.b	"[         ",0	;1a
		dc.b	"]         ",0	;1b
		dc.b	"$1c       ",0	;1c
		dc.b	"num 1     ",0	;1d
		dc.b	"num 2     ",0	;1e
		dc.b	"num 3     ",0	;1f
		dc.b	"a         ",0	;20
		dc.b	"s         ",0	;21
		dc.b	"d         ",0	;22
		dc.b	"f         ",0	;23
		dc.b	"g         ",0	;24
		dc.b	"h         ",0	;25
		dc.b	"j         ",0	;26
		dc.b	"k         ",0	;27
		dc.b	"l         ",0	;28
		dc.b	";         ",0	;29
		dc.b	"'         ",0	;2a
		dc.b	"$2b       ",0	;2b
		dc.b	"$2c       ",0	;2c
		dc.b	"num 4     ",0	;2d
		dc.b	"num 5     ",0	;2e
		dc.b	"num 6     ",0	;2f
		dc.b	"<         ",0	;30
		dc.b	"z         ",0	;31
		dc.b	"x         ",0	;32
		dc.b	"c         ",0	;33
		dc.b	"v         ",0	;34
		dc.b	"b         ",0	;35
		dc.b	"n         ",0	;36
		dc.b	"m         ",0	;37
		dc.b	",         ",0	;38
		dc.b	".         ",0	;39
		dc.b	"/         ",0	;3a
		dc.b	"$3b       ",0	;3b
		dc.b	"num .     ",0	;3c
		dc.b	"num 7     ",0	;3d
		dc.b	"num 8     ",0	;3e
		dc.b	"num 9     ",0	;3f
		dc.b	"space     ",0	;40
		dc.b	"backspace ",0	;41
		dc.b	"tab       ",0	;42
		dc.b	"num enter ",0	;43
		dc.b	"enter     ",0	;44
		dc.b	"esc       ",0	;45
		dc.b	"del       ",0	;46
		dc.b	"$47       ",0	;47
		dc.b	"$48       ",0	;48
		dc.b	"$49       ",0	;49
		dc.b	"num -     ",0	;4a
		dc.b	"$4b       ",0	;4b
		dc.b	"crsr up   ",0	;4c
		dc.b	"crsr down ",0	;4d
		dc.b	"crsr right",0	;4e
		dc.b	"crsr left ",0	;4f
		dc.b	"f1        ",0	;50
		dc.b	"f2        ",0	;51
		dc.b	"f3        ",0	;52
		dc.b	"f4        ",0	;53
		dc.b	"f5        ",0	;54
		dc.b	"f6        ",0	;55
		dc.b	"f7        ",0	;56
		dc.b	"f8        ",0	;57
		dc.b	"f9        ",0	;58
		dc.b	"f10       ",0	;59
		dc.b	"num [     ",0	;5a
		dc.b	"num ]     ",0	;5b
		dc.b	"num /     ",0	;5c
		dc.b	"num *     ",0	;5d
		dc.b	"num +     ",0	;5e
		dc.b	"help      ",0	;5f
		dc.b	"l. shift  ",0	;60
		dc.b	"r. shift  ",0	;61
		dc.b	"caps lock ",0	;62
		dc.b	"ctrl      ",0	;63
		dc.b	"l. alt    ",0	;64
		dc.b	"r. alt    ",0	;65
		dc.b	"l. amiga  ",0	;66
		dc.b	"r. amiga  ",0	;67
		dc.b	"$68       ",0	;68
		dc.b	"$69       ",0	;69
		dc.b	"$6a       ",0	;6a
		dc.b	"$6b       ",0	;6b
		dc.b	"$6c       ",0	;6c
		dc.b	"$6d       ",0	;6d
		dc.b	"$6e       ",0	;6e
		dc.b	"$6f       ",0	;6f
		dc.b	"$70       ",0	;70
		dc.b	"$71       ",0	;71
		dc.b	"$72       ",0	;72
		dc.b	"$73       ",0	;73
		dc.b	"$74       ",0	;74
		dc.b	"$75       ",0	;75
		dc.b	"$76       ",0	;76
		dc.b	"$77       ",0	;77
		dc.b	"$78       ",0	;78
		dc.b	"$79       ",0	;79
		dc.b	"$7a       ",0	;7a
		dc.b	"$7b       ",0	;7b
		dc.b	"$7c       ",0	;7c
		dc.b	"$7d       ",0	;7d
		dc.b	"$7e       ",0	;7e
		dc.b	"$7f       ",0	;7f 

pubFonts:
		incbin	'fonts8x8x1.bin'

;-----------------------------------------------------------------------------

	SECTION	gfx,DATA_C

chipCopper:		ds.b	COPPER_SIZE

chipSpriteFake:		dc.l	0,0,0,0

;-----------------------------------------------------------------------------

	SECTION	screens,BSS_C

chipScreen:		ds.b	SCREEN_SIZE

