	; IntyBASIC compiler v1.2.8 Oct/07/2016
        ;
        ; Prologue for IntyBASIC programs
        ; by Oscar Toledo G.  http://nanochess.org/
        ;
        ; Revision: Jan/30/2014. Spacing adjustment and more comments.
        ; Revision: Apr/01/2014. It now sets the starting screen pos. for PRINT
	    ; Revision: Aug/26/2014. Added PAL detection code.
	    ; Revision: Dec/12/2014. Added optimized constant multiplication routines
	    ;                        by James Pujals.
	    ; Revision: Jan/25/2015. Added marker for automatic title replacement.
	    ;                        (option --title of IntyBASIC)
	    ; Revision: Aug/06/2015. Turns off ECS sound. Seed random generator using
	    ;                        trash in 16-bit RAM. Solved bugs and optimized
	    ;                        macro for constant multiplication.
        ; Revision: Jan/12/2016. Solved bug in PAL detection.
        ; Revision: May/03/2016. Changed in _mode_select initialization.
	    ; Revision: Jul/31/2016. Solved bug in multiplication by 126 and 127.
	; Revision: Sep/08/2016. Now CLRSCR initializes screen position for PRINT, this
	;                        solves bug when user programs goes directly to PRINT.
        ;

        ROMW 16
        ORG $5000

        ; This macro will 'eat' SRCFILE directives if the assembler doesn't support the directive.
        IF ( DEFINED __FEATURE.SRCFILE ) = 0
            MACRO SRCFILE x, y
            ; macro must be non-empty, but a comment works fine.
            ENDM
        ENDI

        ;
        ; ROM header
        ;
        BIDECLE _ZERO           ; MOB picture base
        BIDECLE _ZERO           ; Process table
        BIDECLE _MAIN           ; Program start
        BIDECLE _ZERO           ; Background base image
        BIDECLE _ONES           ; GRAM
        BIDECLE _TITLE          ; Cartridge title and date
        DECLE   $03C0           ; No ECS title, jump to code after title,
                                ; ... no clicks
                                
_ZERO:  DECLE   $0000           ; Border control
        DECLE   $0000           ; 0 = color stack, 1 = f/b mode
        
_ONES:  DECLE   $0001, $0001    ; Initial color stack 0 and 1: Blue
        DECLE   $0001, $0001    ; Initial color stack 2 and 3: Blue
        DECLE   $0001           ; Initial border color: Blue

C_WHT:  EQU $0007

CLRSCR: MVII #$200,R4           ; Used also for CLS
	MVO R4,_screen		; Set up starting screen position for PRINT
        MVII #$F0,R1
FILLZERO:
        CLRR R0
MEMSET:
        MVO@ R0,R4
        DECR R1
        BNE MEMSET
        JR R5

        ;
        ; Title, Intellivision EXEC will jump over it and start
        ; execution directly in _MAIN
        ;
	; Note mark is for automatic replacement by IntyBASIC
_TITLE:
	BYTE 118,'runnerZ',0
        
        ;
        ; Main program
        ;
_MAIN:
        DIS
        MVII #STACK,R6

_MAIN0:
        ;
        ; Clean memory
        ;
        MVII #$00e,R1           ; 14 of sound (ECS)
        MVII #$0f0,R4           ; ECS PSG
        CALL FILLZERO
        MVII #$0fe,R1           ; 240 words of 8 bits plus 14 of sound
        MVII #$100,R4           ; 8-bit scratch RAM
        CALL FILLZERO

	; Seed random generator using 16 bit RAM (not cleared by EXEC)
	CLRR R0
	MVII #$02F0,R4
	MVII #$0110/4,R1        ; Includes phantom memory for extra randomness
_MAIN4:                         ; This loop is courtesy of GroovyBee
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	ADD@ R4,R0
	DECR R1
	BNE _MAIN4
	MVO R0,_rand

        MVII #$058,R1           ; 88 words of 16 bits
        MVII #$308,R4           ; 16-bit scratch RAM
        CALL FILLZERO

        CALL CLRSCR             ; Clean up screen

        MVII #_pal1_vector,R0 ; Points to interrupt vector
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1

        EIS

_MAIN1:	MVI _ntsc,R0
	CMPI #3,R0
	BNE _MAIN1
	CLRR R2
_MAIN2:	INCR R2
	MVI _ntsc,R0
	CMPI #4,R0
	BNE _MAIN2

        ; 596 for PAL in jzintv
        ; 444 for NTSC in jzintv
        CMPI #520,R2
        MVII #1,R0
        BLE _MAIN3
        CLRR R0
_MAIN3: MVO R0,_ntsc

        CALL _wait
	CALL _init_music
        MVII #2,R0
        MVO R0,_mode_select
        MVII #$038,R0
        MVO R0,$01F8            ; Configures sound
        MVO R0,$00F8            ; Configures sound (ECS)
        CALL _wait

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- James Pujals (DZ-Jay), 2014                              *;
;* ======================================================================== *;

; Modified by Oscar Toledo G. (nanochess), Aug/06/2015
; * Tested all multiplications with automated test.
; * Accelerated multiplication by 7,14,15,28,31,60,62,63,112,120,124
; * Solved bug in multiplication by 23,39,46,47,55,71,78,79,87,92,93,94,95,103,110,111,119
; * Improved sequence of instructions to be more interruptible.

;; ======================================================================== ;;
;;  MULT reg, tmp, const                                                    ;;
;;  Multiplies "reg" by constant "const" and using "tmp" for temporary      ;;
;;  calculations.  The result is placed in "reg."  The multiplication is    ;;
;;  performed by an optimal combination of shifts, additions, and           ;;
;;  subtractions.                                                           ;;
;;                                                                          ;;
;;  NOTE:   The resulting contents of the "tmp" are undefined.              ;;
;;                                                                          ;;
;;  ARGUMENTS                                                               ;;
;;      reg         A register containing the multiplicand.                 ;;
;;      tmp         A register for temporary calculations.                  ;;
;;      const       The constant multiplier.                                ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      reg         Output value.                                           ;;
;;      tmp         Trashed.                                                ;;
;;      .ERR.Failed True if operation failed.                               ;;
;; ======================================================================== ;;
MACRO   MULT reg, tmp, const
;
    LISTING "code"

_mul.const      QSET    %const%
_mul.done       QSET    0

        IF (%const% > $7F)
_mul.const      QSET    (_mul.const SHR 1)
                SLL     %reg%,  1
        ENDI

        ; Multiply by $00 (0)
        IF (_mul.const = $00)
_mul.done       QSET    -1
                CLRR    %reg%
        ENDI

        ; Multiply by $01 (1)
        IF (_mul.const = $01)
_mul.done       QSET    -1
                ; Nothing to do
        ENDI

        ; Multiply by $02 (2)
        IF (_mul.const = $02)
_mul.done       QSET    -1
                SLL     %reg%,  1
        ENDI

        ; Multiply by $03 (3)
        IF (_mul.const = $03)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $04 (4)
        IF (_mul.const = $04)
_mul.done       QSET    -1
                SLL     %reg%,  2
        ENDI

        ; Multiply by $05 (5)
        IF (_mul.const = $05)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $06 (6)
        IF (_mul.const = $06)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $07 (7)
        IF (_mul.const = $07)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $08 (8)
        IF (_mul.const = $08)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
        ENDI

        ; Multiply by $09 (9)
        IF (_mul.const = $09)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0A (10)
        IF (_mul.const = $0A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0B (11)
        IF (_mul.const = $0B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0C (12)
        IF (_mul.const = $0C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0D (13)
        IF (_mul.const = $0D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0E (14)
        IF (_mul.const = $0E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $0F (15)
        IF (_mul.const = $0F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $10 (16)
        IF (_mul.const = $10)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $11 (17)
        IF (_mul.const = $11)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $12 (18)
        IF (_mul.const = $12)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $13 (19)
        IF (_mul.const = $13)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $14 (20)
        IF (_mul.const = $14)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $15 (21)
        IF (_mul.const = $15)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $16 (22)
        IF (_mul.const = $16)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $17 (23)
        IF (_mul.const = $17)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $18 (24)
        IF (_mul.const = $18)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $19 (25)
        IF (_mul.const = $19)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1A (26)
        IF (_mul.const = $1A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1B (27)
        IF (_mul.const = $1B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1C (28)
        IF (_mul.const = $1C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1D (29)
        IF (_mul.const = $1D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1E (30)
        IF (_mul.const = $1E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $1F (31)
        IF (_mul.const = $1F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $20 (32)
        IF (_mul.const = $20)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
        ENDI

        ; Multiply by $21 (33)
        IF (_mul.const = $21)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $22 (34)
        IF (_mul.const = $22)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $23 (35)
        IF (_mul.const = $23)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $24 (36)
        IF (_mul.const = $24)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $25 (37)
        IF (_mul.const = $25)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $26 (38)
        IF (_mul.const = $26)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $27 (39)
        IF (_mul.const = $27)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $28 (40)
        IF (_mul.const = $28)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $29 (41)
        IF (_mul.const = $29)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2A (42)
        IF (_mul.const = $2A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2B (43)
        IF (_mul.const = $2B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2C (44)
        IF (_mul.const = $2C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2D (45)
        IF (_mul.const = $2D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $2E (46)
        IF (_mul.const = $2E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $2F (47)
        IF (_mul.const = $2F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,  %reg%
        ENDI

        ; Multiply by $30 (48)
        IF (_mul.const = $30)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $31 (49)
        IF (_mul.const = $31)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $32 (50)
        IF (_mul.const = $32)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $33 (51)
        IF (_mul.const = $33)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $34 (52)
        IF (_mul.const = $34)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $35 (53)
        IF (_mul.const = $35)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $36 (54)
        IF (_mul.const = $36)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $37 (55)
        IF (_mul.const = $37)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
		SLL	%reg%,	1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $38 (56)
        IF (_mul.const = $38)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $39 (57)
        IF (_mul.const = $39)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3A (58)
        IF (_mul.const = $3A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3B (59)
        IF (_mul.const = $3B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3C (60)
        IF (_mul.const = $3C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3D (61)
        IF (_mul.const = $3D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3E (62)
        IF (_mul.const = $3E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $3F (63)
        IF (_mul.const = $3F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $40 (64)
        IF (_mul.const = $40)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
        ENDI

        ; Multiply by $41 (65)
        IF (_mul.const = $41)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $42 (66)
        IF (_mul.const = $42)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $43 (67)
        IF (_mul.const = $43)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $44 (68)
        IF (_mul.const = $44)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $45 (69)
        IF (_mul.const = $45)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $46 (70)
        IF (_mul.const = $46)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $47 (71)
        IF (_mul.const = $47)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $48 (72)
        IF (_mul.const = $48)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $49 (73)
        IF (_mul.const = $49)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4A (74)
        IF (_mul.const = $4A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4B (75)
        IF (_mul.const = $4B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4C (76)
        IF (_mul.const = $4C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4D (77)
        IF (_mul.const = $4D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $4E (78)
        IF (_mul.const = $4E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $4F (79)
        IF (_mul.const = $4F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $50 (80)
        IF (_mul.const = $50)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $51 (81)
        IF (_mul.const = $51)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $52 (82)
        IF (_mul.const = $52)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $53 (83)
        IF (_mul.const = $53)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $54 (84)
        IF (_mul.const = $54)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $55 (85)
        IF (_mul.const = $55)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $56 (86)
        IF (_mul.const = $56)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $57 (87)
        IF (_mul.const = $57)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR    %reg%,	%tmp%
                SLL     %reg%,  2
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $58 (88)
        IF (_mul.const = $58)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $59 (89)
        IF (_mul.const = $59)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5A (90)
        IF (_mul.const = $5A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5B (91)
        IF (_mul.const = $5B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $5C (92)
        IF (_mul.const = $5C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5D (93)
        IF (_mul.const = $5D)
_mul.done       QSET    -1
		MOVR	%reg%,	%tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5E (94)
        IF (_mul.const = $5E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $5F (95)
        IF (_mul.const = $5F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                ADDR	%reg%,	%reg%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $60 (96)
        IF (_mul.const = $60)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $61 (97)
        IF (_mul.const = $61)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $62 (98)
        IF (_mul.const = $62)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $63 (99)
        IF (_mul.const = $63)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $64 (100)
        IF (_mul.const = $64)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $65 (101)
        IF (_mul.const = $65)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $66 (102)
        IF (_mul.const = $66)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $67 (103)
        IF (_mul.const = $67)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $68 (104)
        IF (_mul.const = $68)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $69 (105)
        IF (_mul.const = $69)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6A (106)
        IF (_mul.const = $6A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6B (107)
        IF (_mul.const = $6B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6C (108)
        IF (_mul.const = $6C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6D (109)
        IF (_mul.const = $6D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $6E (110)
        IF (_mul.const = $6E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $6F (111)
        IF (_mul.const = $6F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
		SUBR	%tmp%,	%reg%
        ENDI

        ; Multiply by $70 (112)
        IF (_mul.const = $70)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $71 (113)
        IF (_mul.const = $71)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $72 (114)
        IF (_mul.const = $72)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $73 (115)
        IF (_mul.const = $73)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $74 (116)
        IF (_mul.const = $74)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $75 (117)
        IF (_mul.const = $75)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $76 (118)
        IF (_mul.const = $76)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $77 (119)
        IF (_mul.const = $77)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $78 (120)
        IF (_mul.const = $78)
_mul.done       QSET    -1
                SLL     %reg%,  2
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $79 (121)
        IF (_mul.const = $79)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7A (122)
        IF (_mul.const = $7A)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7B (123)
        IF (_mul.const = $7B)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  1
                ADDR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7C (124)
        IF (_mul.const = $7C)
_mul.done       QSET    -1
                SLL     %reg%,  2
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7D (125)
        IF (_mul.const = $7D)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SUBR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
		ADDR	%reg%,	%reg%
                ADDR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7E (126)
        IF (_mul.const = $7E)
_mul.done       QSET    -1
                SLL     %reg%,  1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SUBR    %tmp%,  %reg%
        ENDI

        ; Multiply by $7F (127)
        IF (_mul.const = $7F)
_mul.done       QSET    -1
                MOVR    %reg%,  %tmp%
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  2
                SLL     %reg%,  1
                SUBR    %tmp%,  %reg%
        ENDI

        IF  (_mul.done = 0)
            ERR $("Invalid multiplication constant \'%const%\', must be between 0 and ", $#($7F), ".")
        ENDI

    LISTING "prev"
ENDM

;; ======================================================================== ;;
;;  EOF: pm:mac:lang:mult                                                   ;;
;; ======================================================================== ;;

	;FILE C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS
	;[1] ' =========================================================================
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",1
	;[2] ' IntyBASIC SDK Project: RunnerZ V.1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",2
	;[3] ' -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",3
	;[4] '     Programmer: Josue N Rivera
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",4
	;[5] '     Created:    12/14/2017
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",5
	;[6] '     Updated:    12/14/2017
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",6
	;[7] '
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",7
	;[8] ' -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",8
	;[9] ' History:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",9
	;[10] ' 12/14/2017 - runnerZ project created.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",10
	;[11] ' 12/15/2017 - power ups added and the ability to jump.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",11
	;[12] ' 12/16/2017 - animation for level ups and power ups.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",12
	;[13] ' 12/17/2017 - small improvement to animation, power ups and the pause option.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",13
	;[14] ' 12/20/2017 - improvement to animation.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",14
	;[15] ' 12/20/2017 - Version 1 released.
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",15
	;[16] ' 1/11/2018  - Patch to the pause option: display animation instead of changing scene
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",16
	;[17] ' =========================================================================
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",17
	;[18] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",18
	;[19] INCLUDE "constants.bas"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",19
	;FILE C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas
	;[1] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",1
	;[2] REM HEADER - CONSTANTS.BAS
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",2
	;[3] REM
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",3
	;[4] REM Started by Mark Ball, July 2015
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",4
	;[5] REM
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",5
	;[6] REM Constants for use in IntyBASIC
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",6
	;[7] REM
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",7
	;[8] REM HISTORY
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",8
	;[9] REM -------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",9
	;[10] REM 1.00F 05/07/15 - First version.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",10
	;[11] REM 1.01F 07/07/15 - Added disc directions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",11
	;[12] REM                - Added background modes.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",12
	;[13] REM                - Minor comment changes.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",13
	;[14] REM 1.02F 08/07/15 - Renamed constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",14
	;[15] REM                - Added background access information.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",15
	;[16] REM                - Adjustments to layout.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",16
	;[17] REM 1.03F 08/07/15 - Fixed comment delimiter.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",17
	;[18] REM 1.04F 11/07/15 - Added useful functions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",18
	;[19] REM                - Added controller movement mask.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",19
	;[20] REM 1.05F 11/07/15 - Added BACKGROUND constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",20
	;[21] REM 1.06F 11/07/15 - Changed Y, X order to X, Y in DEF FN functions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",21
	;[22] REM 1.07F 11/07/15 - Added colour stack advance.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",22
	;[23] REM 1.08F 12/07/15 - Added functions for sprite position handling.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",23
	;[24] REM 1.09F 12/07/15 - Added a function for resetting a sprite.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",24
	;[25] REM 1.10F 13/07/15 - Added keypad constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",25
	;[26] REM 1.11F 13/07/15 - Added side button constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",26
	;[27] REM 1.12F 13/07/15 - Updated sprite functions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",27
	;[28] REM 1.13F 19/07/15 - Added border masking constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",28
	;[29] REM 1.14F 20/07/15 - Added a combined border masking constant.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",29
	;[30] REM 1.15F 20/07/15 - Renamed border masking constants to BORDER_HIDE_xxxx.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",30
	;[31] REM 1.16F 28/09/15 - Fixed disc direction typos.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",31
	;[32] REM 1.17F 30/09/15 - Fixed DISC_SOUTH_WEST value.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",32
	;[33] REM 1.18F 05/12/15 - Fixed BG_XXXX colours.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",33
	;[34] REM 1.19F 01/01/16 - Changed name of BACKTAB constant to avoid confusion with #BACKTAB array.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",34
	;[35] REM                - Added pause key constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",35
	;[36] REM 1.20F 14/01/16 - Added coloured squares mode's pixel colours.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",36
	;[37] REM 1.21F 15/01/16 - Added coloured squares mode's X and Y limits.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",37
	;[38] REM 1.22F 23/01/16 - Added PSG constants.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",38
	;[39] REM 1.23F 24/01/16 - Fixed typo in PSG comments.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",39
	;[40] REM 1.24F 16/11/16 - Added toggle DEF FN's for sprite's BEHIND, HIT and VISIBLE.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",40
	;[41] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",41
	;[42] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",42
	;[43] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",43
	;[44] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",44
	;[45] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",45
	;[46] REM Background information.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",46
	;[47] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",47
	;[48] CONST BACKTAB_ADDR					= $0200		' Start of the BACKground TABle (BACKTAB) in RAM.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",48
	;[49] CONST BACKGROUND_ROWS				= 12		' Height of the background in cards.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",49
	;[50] CONST BACKGROUND_COLUMNS			= 20		' Width of the background in cards.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",50
	;[51] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",51
	;[52] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",52
	;[53] REM Background GRAM cards.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",53
	;[54] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",54
	;[55] CONST BG00							= $0800
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",55
	;[56] CONST BG01							= $0808
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",56
	;[57] CONST BG02							= $0810
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",57
	;[58] CONST BG03							= $0818
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",58
	;[59] CONST BG04							= $0820
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",59
	;[60] CONST BG05							= $0828
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",60
	;[61] CONST BG06							= $0830
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",61
	;[62] CONST BG07							= $0838
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",62
	;[63] CONST BG08							= $0840
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",63
	;[64] CONST BG09							= $0848
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",64
	;[65] CONST BG10							= $0850
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",65
	;[66] CONST BG11							= $0858
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",66
	;[67] CONST BG12							= $0860
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",67
	;[68] CONST BG13							= $0868
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",68
	;[69] CONST BG14							= $0870
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",69
	;[70] CONST BG15							= $0878
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",70
	;[71] CONST BG16							= $0880
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",71
	;[72] CONST BG17							= $0888
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",72
	;[73] CONST BG18							= $0890
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",73
	;[74] CONST BG19							= $0898
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",74
	;[75] CONST BG20							= $08A0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",75
	;[76] CONST BG21							= $08A8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",76
	;[77] CONST BG22							= $08B0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",77
	;[78] CONST BG23							= $08B8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",78
	;[79] CONST BG24							= $08C0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",79
	;[80] CONST BG25							= $08C8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",80
	;[81] CONST BG26							= $08D0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",81
	;[82] CONST BG27							= $08D8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",82
	;[83] CONST BG28							= $08E0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",83
	;[84] CONST BG29							= $08E8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",84
	;[85] CONST BG30							= $08F0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",85
	;[86] CONST BG31							= $08F8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",86
	;[87] CONST BG32							= $0900
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",87
	;[88] CONST BG33							= $0908
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",88
	;[89] CONST BG34							= $0910
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",89
	;[90] CONST BG35							= $0918
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",90
	;[91] CONST BG36							= $0920
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",91
	;[92] CONST BG37							= $0928
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",92
	;[93] CONST BG38							= $0930
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",93
	;[94] CONST BG39							= $0938
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",94
	;[95] CONST BG40							= $0940
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",95
	;[96] CONST BG41							= $0948
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",96
	;[97] CONST BG42							= $0950
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",97
	;[98] CONST BG43							= $0958
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",98
	;[99] CONST BG44							= $0960
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",99
	;[100] CONST BG45							= $0968
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",100
	;[101] CONST BG46							= $0970
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",101
	;[102] CONST BG47							= $0978
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",102
	;[103] CONST BG48							= $0980
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",103
	;[104] CONST BG49							= $0988
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",104
	;[105] CONST BG50							= $0990
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",105
	;[106] CONST BG51							= $0998
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",106
	;[107] CONST BG52							= $09A0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",107
	;[108] CONST BG53							= $09A8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",108
	;[109] CONST BG54							= $09B0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",109
	;[110] CONST BG55							= $09B8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",110
	;[111] CONST BG56							= $09C0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",111
	;[112] CONST BG57							= $09C8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",112
	;[113] CONST BG58							= $09D0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",113
	;[114] CONST BG59							= $09D8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",114
	;[115] CONST BG60							= $09E0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",115
	;[116] CONST BG61							= $09E8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",116
	;[117] CONST BG62							= $09F0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",117
	;[118] CONST BG63							= $09F8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",118
	;[119] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",119
	;[120] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",120
	;[121] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",121
	;[122] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",122
	;[123] REM GRAM card index numbers.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",123
	;[124] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",124
	;[125] REM Note: For use with the "define" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",125
	;[126] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",126
	;[127] CONST DEF00							= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",127
	;[128] CONST DEF01							= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",128
	;[129] CONST DEF02							= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",129
	;[130] CONST DEF03							= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",130
	;[131] CONST DEF04							= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",131
	;[132] CONST DEF05							= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",132
	;[133] CONST DEF06							= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",133
	;[134] CONST DEF07							= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",134
	;[135] CONST DEF08							= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",135
	;[136] CONST DEF09							= $0009
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",136
	;[137] CONST DEF10							= $000A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",137
	;[138] CONST DEF11							= $000B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",138
	;[139] CONST DEF12							= $000C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",139
	;[140] CONST DEF13							= $000D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",140
	;[141] CONST DEF14							= $000E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",141
	;[142] CONST DEF15							= $000F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",142
	;[143] CONST DEF16							= $0010
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",143
	;[144] CONST DEF17							= $0011
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",144
	;[145] CONST DEF18							= $0012
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",145
	;[146] CONST DEF19							= $0013
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",146
	;[147] CONST DEF20							= $0014
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",147
	;[148] CONST DEF21							= $0015
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",148
	;[149] CONST DEF22							= $0016
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",149
	;[150] CONST DEF23							= $0017
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",150
	;[151] CONST DEF24							= $0018
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",151
	;[152] CONST DEF25							= $0019
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",152
	;[153] CONST DEF26							= $001A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",153
	;[154] CONST DEF27							= $001B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",154
	;[155] CONST DEF28							= $001C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",155
	;[156] CONST DEF29							= $001D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",156
	;[157] CONST DEF30							= $001E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",157
	;[158] CONST DEF31							= $001F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",158
	;[159] CONST DEF32							= $0020
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",159
	;[160] CONST DEF33							= $0021
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",160
	;[161] CONST DEF34							= $0022
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",161
	;[162] CONST DEF35							= $0023
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",162
	;[163] CONST DEF36							= $0024
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",163
	;[164] CONST DEF37							= $0025
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",164
	;[165] CONST DEF38							= $0026
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",165
	;[166] CONST DEF39							= $0027
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",166
	;[167] CONST DEF40							= $0028
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",167
	;[168] CONST DEF41							= $0029
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",168
	;[169] CONST DEF42							= $002A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",169
	;[170] CONST DEF43							= $002B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",170
	;[171] CONST DEF44							= $002C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",171
	;[172] CONST DEF45							= $002D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",172
	;[173] CONST DEF46							= $002E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",173
	;[174] CONST DEF47							= $002F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",174
	;[175] CONST DEF48							= $0030
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",175
	;[176] CONST DEF49							= $0031
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",176
	;[177] CONST DEF50							= $0032
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",177
	;[178] CONST DEF51							= $0033
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",178
	;[179] CONST DEF52							= $0034
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",179
	;[180] CONST DEF53							= $0035
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",180
	;[181] CONST DEF54							= $0036
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",181
	;[182] CONST DEF55							= $0037
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",182
	;[183] CONST DEF56							= $0038
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",183
	;[184] CONST DEF57							= $0039
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",184
	;[185] CONST DEF58							= $003A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",185
	;[186] CONST DEF59							= $003B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",186
	;[187] CONST DEF60							= $003C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",187
	;[188] CONST DEF61							= $003D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",188
	;[189] CONST DEF62							= $003E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",189
	;[190] CONST DEF63							= $003F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",190
	;[191] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",191
	;[192] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",192
	;[193] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",193
	;[194] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",194
	;[195] REM Screen modes.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",195
	;[196] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",196
	;[197] REM Note: For use with the "mode" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",197
	;[198] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",198
	;[199] CONST SCREEN_COLOR_STACK			= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",199
	;[200] CONST SCREEN_FOREGROUND_BACKGROUND	= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",200
	;[201] REM Abbreviated versions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",201
	;[202] CONST SCREEN_FB						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",202
	;[203] CONST SCREEN_CS						= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",203
	;[204] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",204
	;[205] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",205
	;[206] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",206
	;[207] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",207
	;[208] REM COLORS - Border.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",208
	;[209] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",209
	;[210] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",210
	;[211] REM - For use with the commands "mode 0" and "mode 1".
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",211
	;[212] REM - For use with the "border" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",212
	;[213] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",213
	;[214] CONST BORDER_BLACK					= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",214
	;[215] CONST BORDER_BLUE					= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",215
	;[216] CONST BORDER_RED					= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",216
	;[217] CONST BORDER_TAN					= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",217
	;[218] CONST BORDER_DARKGREEN				= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",218
	;[219] CONST BORDER_GREEN					= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",219
	;[220] CONST BORDER_YELLOW					= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",220
	;[221] CONST BORDER_WHITE					= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",221
	;[222] CONST BORDER_GREY					= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",222
	;[223] CONST BORDER_CYAN					= $0009
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",223
	;[224] CONST BORDER_ORANGE					= $000A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",224
	;[225] CONST BORDER_BROWN					= $000B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",225
	;[226] CONST BORDER_PINK					= $000C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",226
	;[227] CONST BORDER_LIGHTBLUE				= $000D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",227
	;[228] CONST BORDER_YELLOWGREEN			= $000E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",228
	;[229] CONST BORDER_PURPLE					= $000F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",229
	;[230] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",230
	;[231] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",231
	;[232] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",232
	;[233] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",233
	;[234] REM BORDER - Edge masks.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",234
	;[235] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",235
	;[236] REM Note: For use with the "border color, edge" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",236
	;[237] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",237
	;[238] CONST BORDER_HIDE_LEFT_EDGE			= $0001		' Hide the leftmost column of the background.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",238
	;[239] CONST BORDER_HIDE_TOP_EDGE			= $0002		' Hide the topmost row of the background.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",239
	;[240] CONST BORDER_HIDE_TOP_LEFT_EDGE		= $0003		' Hide both the topmost row and leftmost column of the background.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",240
	;[241] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",241
	;[242] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",242
	;[243] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",243
	;[244] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",244
	;[245] REM COLORS - Mode 0 (Color Stack).
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",245
	;[246] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",246
	;[247] REM Stack
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",247
	;[248] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",248
	;[249] REM Note: For use as the last 4 parameters used in the "mode 1" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",249
	;[250] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",250
	;[251] CONST STACK_BLACK					= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",251
	;[252] CONST STACK_BLUE					= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",252
	;[253] CONST STACK_RED						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",253
	;[254] CONST STACK_TAN						= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",254
	;[255] CONST STACK_DARKGREEN				= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",255
	;[256] CONST STACK_GREEN					= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",256
	;[257] CONST STACK_YELLOW					= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",257
	;[258] CONST STACK_WHITE					= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",258
	;[259] CONST STACK_GREY					= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",259
	;[260] CONST STACK_CYAN					= $0009
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",260
	;[261] CONST STACK_ORANGE					= $000A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",261
	;[262] CONST STACK_BROWN					= $000B
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",262
	;[263] CONST STACK_PINK					= $000C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",263
	;[264] CONST STACK_LIGHTBLUE				= $000D
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",264
	;[265] CONST STACK_YELLOWGREEN				= $000E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",265
	;[266] CONST STACK_PURPLE					= $000F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",266
	;[267] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",267
	;[268] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",268
	;[269] REM Foreground.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",269
	;[270] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",270
	;[271] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",271
	;[272] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",272
	;[273] REM - Only one foreground colour permitted per background card.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",273
	;[274] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",274
	;[275] CONST CS_BLACK						= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",275
	;[276] CONST CS_BLUE						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",276
	;[277] CONST CS_RED						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",277
	;[278] CONST CS_TAN						= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",278
	;[279] CONST CS_DARKGREEN					= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",279
	;[280] CONST CS_GREEN						= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",280
	;[281] CONST CS_YELLOW						= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",281
	;[282] CONST CS_WHITE						= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",282
	;[283] CONST CS_GREY						= $1000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",283
	;[284] CONST CS_CYAN						= $1001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",284
	;[285] CONST CS_ORANGE						= $1002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",285
	;[286] CONST CS_BROWN						= $1003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",286
	;[287] CONST CS_PINK						= $1004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",287
	;[288] CONST CS_LIGHTBLUE					= $1005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",288
	;[289] CONST CS_YELLOWGREEN				= $1006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",289
	;[290] CONST CS_PURPLE						= $1007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",290
	;[291] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",291
	;[292] CONST CS_CARD_DATA_MASK				= $07F8		' Mask to get the background card's data.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",292
	;[293] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",293
	;[294] CONST CS_ADVANCE					= $2000		' Advance the colour stack by one position.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",294
	;[295] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",295
	;[296] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",296
	;[297] REM Coloured squares mode.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",297
	;[298] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",298
	;[299] REM Notes :
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",299
	;[300] REM - Only available in colour stack mode.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",300
	;[301] REM - Pixels in each BACKTAB card are arranged in the following manner:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",301
	;[302] REM +-------+-------+
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",302
	;[303] REM | Pixel | Pixel |
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",303
	;[304] REM |   0   |   1   !
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",304
	;[305] REM +-------+-------+
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",305
	;[306] REM | Pixel | Pixel |
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",306
	;[307] REM |   2   |   3   !
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",307
	;[308] REM +-------+-------+
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",308
	;[309] REM
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",309
	;[310] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",310
	;[311] CONST CS_COLOUR_SQUARES_ENABLE		= $1000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",311
	;[312] CONST CS_PIX0_BLACK					= 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",312
	;[313] CONST CS_PIX0_BLUE					= 1
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",313
	;[314] CONST CS_PIX0_RED					= 2
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",314
	;[315] CONST CS_PIX0_TAN					= 3
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",315
	;[316] CONST CS_PIX0_DARKGREEN				= 4
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",316
	;[317] CONST CS_PIX0_GREEN					= 5
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",317
	;[318] CONST CS_PIX0_YELLOW				= 6
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",318
	;[319] CONST CS_PIX0_BACKGROUND			= 7
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",319
	;[320] CONST CS_PIX1_BLACK					= 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",320
	;[321] CONST CS_PIX1_BLUE					= 1*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",321
	;[322] CONST CS_PIX1_RED					= 2*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",322
	;[323] CONST CS_PIX1_TAN					= 3*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",323
	;[324] CONST CS_PIX1_DARKGREEN				= 4*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",324
	;[325] CONST CS_PIX1_GREEN					= 5*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",325
	;[326] CONST CS_PIX1_YELLOW				= 6*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",326
	;[327] CONST CS_PIX1_BACKGROUND			= 7*8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",327
	;[328] CONST CS_PIX2_BLACK					= 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",328
	;[329] CONST CS_PIX2_BLUE					= 1*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",329
	;[330] CONST CS_PIX2_RED					= 2*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",330
	;[331] CONST CS_PIX2_TAN					= 3*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",331
	;[332] CONST CS_PIX2_DARKGREEN				= 4*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",332
	;[333] CONST CS_PIX2_GREEN					= 5*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",333
	;[334] CONST CS_PIX2_YELLOW				= 6*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",334
	;[335] CONST CS_PIX2_BACKGROUND			= 7*64
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",335
	;[336] CONST CS_PIX3_BLACK					= 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",336
	;[337] CONST CS_PIX3_BLUE					= $0200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",337
	;[338] CONST CS_PIX3_RED					= $0400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",338
	;[339] CONST CS_PIX3_TAN					= $0600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",339
	;[340] CONST CS_PIX3_DARKGREEN				= $2000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",340
	;[341] CONST CS_PIX3_GREEN					= $2200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",341
	;[342] CONST CS_PIX3_YELLOW				= $2400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",342
	;[343] CONST CS_PIX3_BACKGROUND			= $2600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",343
	;[344] CONST CS_PIX_MASK					= CS_COLOUR_SQUARES_ENABLE+CS_PIX0_BACKGROUND+CS_PIX1_BACKGROUND+CS_PIX2_BACKGROUND+CS_PIX3_BACKGROUND
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",344
	;[345] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",345
	;[346] CONST CS_PIX_X_MIN					= 0		' Minimum x coordinate.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",346
	;[347] CONST CS_PIX_X_MAX					= 39	' Maximum x coordinate.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",347
	;[348] CONST CS_PIX_Y_MIN					= 0		' Minimum Y coordinate.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",348
	;[349] CONST CS_PIX_Y_MAX					= 23	' Maximum Y coordinate.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",349
	;[350] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",350
	;[351] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",351
	;[352] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",352
	;[353] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",353
	;[354] REM COLORS - Mode 1 (Foreground Background)
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",354
	;[355] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",355
	;[356] REM Foreground.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",356
	;[357] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",357
	;[358] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",358
	;[359] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",359
	;[360] REM - Only one foreground colour permitted per background card.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",360
	;[361] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",361
	;[362] CONST FG_BLACK						= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",362
	;[363] CONST FG_BLUE						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",363
	;[364] CONST FG_RED						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",364
	;[365] CONST FG_TAN						= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",365
	;[366] CONST FG_DARKGREEN					= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",366
	;[367] CONST FG_GREEN						= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",367
	;[368] CONST FG_YELLOW						= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",368
	;[369] CONST FG_WHITE						= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",369
	;[370] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",370
	;[371] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",371
	;[372] REM Background.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",372
	;[373] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",373
	;[374] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",374
	;[375] REM - For use with "peek/poke" commands that access BACKTAB.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",375
	;[376] REM - Only one background colour permitted per background card.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",376
	;[377] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",377
	;[378] CONST BG_BLACK						= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",378
	;[379] CONST BG_BLUE						= $0200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",379
	;[380] CONST BG_RED						= $0400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",380
	;[381] CONST BG_TAN						= $0600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",381
	;[382] CONST BG_DARKGREEN					= $2000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",382
	;[383] CONST BG_GREEN						= $2200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",383
	;[384] CONST BG_YELLOW						= $2400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",384
	;[385] CONST BG_WHITE						= $2600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",385
	;[386] CONST BG_GREY						= $1000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",386
	;[387] CONST BG_CYAN						= $1200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",387
	;[388] CONST BG_ORANGE						= $1400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",388
	;[389] CONST BG_BROWN						= $1600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",389
	;[390] CONST BG_PINK						= $3000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",390
	;[391] CONST BG_LIGHTBLUE					= $3200
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",391
	;[392] CONST BG_YELLOWGREEN				= $3400
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",392
	;[393] CONST BG_PURPLE						= $3600
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",393
	;[394] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",394
	;[395] CONST FGBG_CARD_DATA_MASK			= $01F8		' Mask to get the background card's data.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",395
	;[396] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",396
	;[397] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",397
	;[398] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",398
	;[399] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",399
	;[400] REM Sprites.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",400
	;[401] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",401
	;[402] REM Note: For use with "sprite" command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",402
	;[403] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",403
	;[404] REM X
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",404
	;[405] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",405
	;[406] REM Note: Add these constants to the sprite command's X parameter.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",406
	;[407] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",407
	;[408] CONST HIT							= $0100		' Enable the sprite's collision detection.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",408
	;[409] CONST VISIBLE						= $0200		' Make the sprite visible.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",409
	;[410] CONST ZOOMX2						= $0400		' Make the sprite twice the width.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",410
	;[411] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",411
	;[412] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",412
	;[413] REM Y
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",413
	;[414] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",414
	;[415] REM Note: Add these constants to the sprite command's Y parameter.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",415
	;[416] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",416
	;[417] CONST DOUBLEY						= $0080		' Make a double height sprite (with 2 GRAM cards).
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",417
	;[418] CONST ZOOMY2						= $0100		' Make the sprite twice (x2) the normal height.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",418
	;[419] CONST ZOOMY4						= $0200		' Make the sprite quadruple (x4) the normal height.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",419
	;[420] CONST ZOOMY8						= $0300		' Make the sprite octuple (x8) the normal height.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",420
	;[421] CONST FLIPX							= $0400		' Flip/mirror the sprite in X.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",421
	;[422] CONST FLIPY							= $0800		' Flip/mirror the sprite in Y.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",422
	;[423] CONST MIRROR						= $0C00		' Flip/mirror the sprite in both X and Y.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",423
	;[424] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",424
	;[425] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",425
	;[426] REM A
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",426
	;[427] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",427
	;[428] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",428
	;[429] REM - Combine to create the sprite command's A parameter.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",429
	;[430] REM - Only one colour per sprite.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",430
	;[431] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",431
	;[432] CONST GRAM							= $0800		' Sprite's data is located in GRAM.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",432
	;[433] CONST BEHIND						= $2000		' Sprite is behind the background.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",433
	;[434] CONST SPR_BLACK						= $0000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",434
	;[435] CONST SPR_BLUE						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",435
	;[436] CONST SPR_RED						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",436
	;[437] CONST SPR_TAN						= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",437
	;[438] CONST SPR_DARKGREEN					= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",438
	;[439] CONST SPR_GREEN						= $0005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",439
	;[440] CONST SPR_YELLOW					= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",440
	;[441] CONST SPR_WHITE						= $0007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",441
	;[442] CONST SPR_GREY						= $1000
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",442
	;[443] CONST SPR_CYAN						= $1001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",443
	;[444] CONST SPR_ORANGE					= $1002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",444
	;[445] CONST SPR_BROWN						= $1003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",445
	;[446] CONST SPR_PINK						= $1004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",446
	;[447] CONST SPR_LIGHTBLUE					= $1005
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",447
	;[448] CONST SPR_YELLOWGREEN				= $1006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",448
	;[449] CONST SPR_PURPLE					= $1007
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",449
	;[450] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",450
	;[451] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",451
	;[452] REM GRAM numbers.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",452
	;[453] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",453
	;[454] REM Note: For use in the sprite command's parameter A.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",454
	;[455] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",455
	;[456] CONST SPR00							= $0800
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",456
	;[457] CONST SPR01							= $0808
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",457
	;[458] CONST SPR02							= $0810
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",458
	;[459] CONST SPR03							= $0818
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",459
	;[460] CONST SPR04							= $0820
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",460
	;[461] CONST SPR05							= $0828
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",461
	;[462] CONST SPR06							= $0830
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",462
	;[463] CONST SPR07							= $0838
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",463
	;[464] CONST SPR08							= $0840
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",464
	;[465] CONST SPR09							= $0848
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",465
	;[466] CONST SPR10							= $0850
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",466
	;[467] CONST SPR11							= $0858
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",467
	;[468] CONST SPR12							= $0860
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",468
	;[469] CONST SPR13							= $0868
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",469
	;[470] CONST SPR14							= $0870
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",470
	;[471] CONST SPR15							= $0878
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",471
	;[472] CONST SPR16							= $0880
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",472
	;[473] CONST SPR17							= $0888
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",473
	;[474] CONST SPR18							= $0890
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",474
	;[475] CONST SPR19							= $0898
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",475
	;[476] CONST SPR20							= $08A0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",476
	;[477] CONST SPR21							= $08A8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",477
	;[478] CONST SPR22							= $08B0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",478
	;[479] CONST SPR23							= $08B8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",479
	;[480] CONST SPR24							= $08C0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",480
	;[481] CONST SPR25							= $08C8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",481
	;[482] CONST SPR26							= $08D0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",482
	;[483] CONST SPR27							= $08D8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",483
	;[484] CONST SPR28							= $08E0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",484
	;[485] CONST SPR29							= $08E8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",485
	;[486] CONST SPR30							= $08F0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",486
	;[487] CONST SPR31							= $08F8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",487
	;[488] CONST SPR32							= $0900
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",488
	;[489] CONST SPR33							= $0908
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",489
	;[490] CONST SPR34							= $0910
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",490
	;[491] CONST SPR35							= $0918
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",491
	;[492] CONST SPR36							= $0920
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",492
	;[493] CONST SPR37							= $0928
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",493
	;[494] CONST SPR38							= $0930
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",494
	;[495] CONST SPR39							= $0938
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",495
	;[496] CONST SPR40							= $0940
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",496
	;[497] CONST SPR41							= $0948
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",497
	;[498] CONST SPR42							= $0950
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",498
	;[499] CONST SPR43							= $0958
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",499
	;[500] CONST SPR44							= $0960
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",500
	;[501] CONST SPR45							= $0968
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",501
	;[502] CONST SPR46							= $0970
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",502
	;[503] CONST SPR47							= $0978
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",503
	;[504] CONST SPR48							= $0980
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",504
	;[505] CONST SPR49							= $0988
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",505
	;[506] CONST SPR50							= $0990
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",506
	;[507] CONST SPR51							= $0998
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",507
	;[508] CONST SPR52							= $09A0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",508
	;[509] CONST SPR53							= $09A8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",509
	;[510] CONST SPR54							= $09B0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",510
	;[511] CONST SPR55							= $09B8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",511
	;[512] CONST SPR56							= $09C0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",512
	;[513] CONST SPR57							= $09C8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",513
	;[514] CONST SPR58							= $09D0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",514
	;[515] CONST SPR59							= $09D8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",515
	;[516] CONST SPR60							= $09E0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",516
	;[517] CONST SPR61							= $09E8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",517
	;[518] CONST SPR62							= $09F0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",518
	;[519] CONST SPR63							= $09F8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",519
	;[520] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",520
	;[521] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",521
	;[522] REM Sprite collision.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",522
	;[523] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",523
	;[524] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",524
	;[525] REM - For use with variables COL0, COL1, COL2, COL3, COL4, COL5, COL6 and COL7.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",525
	;[526] REM - More than one collision can occur simultaneously.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",526
	;[527] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",527
	;[528] CONST HIT_SPRITE0					= $0001		' Sprite collided with sprite 0.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",528
	;[529] CONST HIT_SPRITE1					= $0002		' Sprite collided with sprite 1.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",529
	;[530] CONST HIT_SPRITE2					= $0004		' Sprite collided with sprite 2.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",530
	;[531] CONST HIT_SPRITE3					= $0008		' Sprite collided with sprite 3.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",531
	;[532] CONST HIT_SPRITE4					= $0010		' Sprite collided with sprite 4.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",532
	;[533] CONST HIT_SPRITE5					= $0020		' Sprite collided with sprite 5.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",533
	;[534] CONST HIT_SPRITE6					= $0040		' Sprite collided with sprite 6.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",534
	;[535] CONST HIT_SPRITE7					= $0080		' Sprite collided with sprite 7.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",535
	;[536] CONST HIT_BACKGROUND				= $0100		' Sprite collided with a background pixel.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",536
	;[537] CONST HIT_BORDER					= $0200		' Sprite collided with the top/bottom/left/right border.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",537
	;[538] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",538
	;[539] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",539
	;[540] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",540
	;[541] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",541
	;[542] REM DISC - Compass.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",542
	;[543] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",543
	;[544] REM   NW         N         NE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",544
	;[545] REM     \   NNW  |  NNE   /
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",545
	;[546] REM       \      |      /
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",546
	;[547] REM         \    |    /
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",547
	;[548] REM    WNW    \  |  /    ENE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",548
	;[549] REM             \|/
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",549
	;[550] REM  W ----------+---------- E
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",550
	;[552] REM             /|REM    WSW    /  |  \    ESE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",552
	;[556] REM         /    |    REM       /      |      REM     /   SSW  |  SSE   REM   SW         S         SE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",556
	;[557] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",557
	;[558] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",558
	;[559] REM - North points upwards on the hand controller.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",559
	;[560] REM - Directions are listed in a clockwise manner.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",560
	;[561] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",561
	;[562] CONST DISC_NORTH					= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",562
	;[563] CONST DISC_NORTH_NORTH_EAST 		= $0014
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",563
	;[564] CONST DISC_NORTH_EAST				= $0016
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",564
	;[565] CONST DISC_EAST_NORTH_EAST			= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",565
	;[566] CONST DISC_EAST						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",566
	;[567] CONST DISC_EAST_SOUTH_EAST			= $0012
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",567
	;[568] CONST DISC_SOUTH_EAST				= $0013
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",568
	;[569] CONST DISC_SOUTH_SOUTH_EAST			= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",569
	;[570] CONST DISC_SOUTH					= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",570
	;[571] CONST DISC_SOUTH_SOUTH_WEST			= $0011
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",571
	;[572] CONST DISC_SOUTH_WEST				= $0019
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",572
	;[573] CONST DISC_WEST_SOUTH_WEST			= $0009
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",573
	;[574] CONST DISC_WEST						= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",574
	;[575] CONST DISC_WEST_NORTH_WEST			= $0018
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",575
	;[576] CONST DISC_NORTH_WEST				= $001C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",576
	;[577] CONST DISC_NORTH_NORTH_WEST			= $000C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",577
	;[578] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",578
	;[579] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",579
	;[580] REM DISC - Compass abbreviated versions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",580
	;[581] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",581
	;[582] CONST DISC_N						= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",582
	;[583] CONST DISC_NNE						= $0014
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",583
	;[584] CONST DISC_NE						= $0016
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",584
	;[585] CONST DISC_ENE						= $0006
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",585
	;[586] CONST DISC_E						= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",586
	;[587] CONST DISC_ESE						= $0012
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",587
	;[588] CONST DISC_SE						= $0013
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",588
	;[589] CONST DISC_SSE						= $0003
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",589
	;[590] CONST DISC_S						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",590
	;[591] CONST DISC_SSW						= $0011
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",591
	;[592] CONST DISC_SW						= $0019
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",592
	;[593] CONST DISC_WSW						= $0009
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",593
	;[594] CONST DISC_W						= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",594
	;[595] CONST DISC_WNW						= $0018
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",595
	;[596] CONST DISC_NW						= $001C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",596
	;[597] CONST DISC_NNW						= $000C
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",597
	;[598] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",598
	;[599] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",599
	;[600] REM DISC - Directions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",600
	;[601] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",601
	;[602] CONST DISC_UP						= $0004
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",602
	;[603] CONST DISC_UP_RIGHT					= $0016		' Up and right diagonal.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",603
	;[604] CONST DISC_RIGHT					= $0002
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",604
	;[605] CONST DISC_DOWN_RIGHT				= $0013		' Down  and right diagonal.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",605
	;[606] CONST DISC_DOWN						= $0001
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",606
	;[607] CONST DISC_DOWN_LEFT				= $0019		' Down and left diagonal.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",607
	;[608] CONST DISC_LEFT						= $0008
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",608
	;[609] CONST DISC_UP_LEFT					= $001C		' Up and left diagonal.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",609
	;[610] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",610
	;[611] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",611
	;[612] REM DISK - Mask.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",612
	;[613] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",613
	;[614] CONST DISK_MASK						= $001F
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",614
	;[615] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",615
	;[616] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",616
	;[617] REM Controller - Keypad.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",617
	;[618] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",618
	;[619] CONST KEYPAD_0						= 72
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",619
	;[620] CONST KEYPAD_1						= 129
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",620
	;[621] CONST KEYPAD_2						= 65
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",621
	;[622] CONST KEYPAD_3						= 33
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",622
	;[623] CONST KEYPAD_4						= 130
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",623
	;[624] CONST KEYPAD_5						= 66
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",624
	;[625] CONST KEYPAD_6						= 34
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",625
	;[626] CONST KEYPAD_7						= 132
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",626
	;[627] CONST KEYPAD_8						= 68
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",627
	;[628] CONST KEYPAD_9						= 36
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",628
	;[629] CONST KEYPAD_CLEAR					= 136
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",629
	;[630] CONST KEYPAD_ENTER					= 40
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",630
	;[631] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",631
	;[632] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",632
	;[633] REM Controller - Pause buttons (1+9 or 3+7 held down simultaneously).
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",633
	;[634] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",634
	;[635] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",635
	;[636] REM - Key codes for 3+7 and 1+9 are the same (165).
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",636
	;[637] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",637
	;[638] CONST KEYPAD_PAUSE					= (KEYPAD_1 XOR KEYPAD_9)
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",638
	;[639] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",639
	;[640] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",640
	;[641] REM Controller - Side buttons.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",641
	;[642] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",642
	;[643] CONST BUTTON_TOP_LEFT				= $A0		' Top left and top right are the same button.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",643
	;[644] CONST BUTTON_TOP_RIGHT				= $A0		' Note: Bit 6 is low.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",644
	;[645] CONST BUTTON_BOTTOM_LEFT			= $60		' Note: Bit 7 is low.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",645
	;[646] CONST BUTTON_BOTTOM_RIGHT			= $C0		' Note: Bit 5 is low
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",646
	;[647] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",647
	;[648] REM Abbreviated versions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",648
	;[649] CONST BUTTON_1						= $A0		' Top left or top right.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",649
	;[650] CONST BUTTON_2						= $60		' Bottom left.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",650
	;[651] CONST BUTTON_3						= $C0		' Bottom right.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",651
	;[652] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",652
	;[653] REM Mask.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",653
	;[654] CONST BUTTON_MASK					= $E0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",654
	;[655] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",655
	;[656] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",656
	;[657] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",657
	;[658] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",658
	;[659] REM Programmable Sound Generator (PSG)
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",659
	;[660] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",660
	;[661] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",661
	;[662] REM - For use with the SOUND command
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",662
	;[663] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",663
	;[664] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",664
	;[665] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",665
	;[666] REM Internal sound hardware.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",666
	;[667] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",667
	;[668] CONST PSG_CHANNELA					= 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",668
	;[669] CONST PSG_CHANNELB					= 1
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",669
	;[670] CONST PSG_CHANNELC					= 2
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",670
	;[671] CONST PSG_ENVELOPE					= 3
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",671
	;[672] CONST PSG_MIXER						= 4
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",672
	;[673] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",673
	;[674] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",674
	;[675] REM ECS sound hardware.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",675
	;[676] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",676
	;[677] CONST PSG_ECS_CHANNELA				= 5
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",677
	;[678] CONST PSG_ECS_CHANNELB				= 6
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",678
	;[679] CONST PSG_ECS_CHANNELC				= 7
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",679
	;[680] CONST PSG_ECS_ENVELOPE				= 8
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",680
	;[681] CONST PSG_ECS_MIXER					= 9
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",681
	;[682] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",682
	;[683] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",683
	;[684] REM PSG - Volume control.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",684
	;[685] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",685
	;[686] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",686
	;[687] REM - For use in the volume field of the SOUND command.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",687
	;[688] REM - Internal channels: PSG_CHANNELA, PSG_CHANNELB, PSG_CHANNELC
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",688
	;[689] REM - ECS channels: PSG_ECS_CHANNELA, PSG_ECS_CHANNELB, PSG_ECS_CHANNELC
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",689
	;[690] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",690
	;[691] CONST PSG_VOLUME_MAX				= 15	' Maximum channel volume.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",691
	;[692] CONST PSG_ENVELOPE_ENABLE			= 48	' Channel volume is controlled by envelope generator.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",692
	;[693] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",693
	;[694] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",694
	;[695] REM PSG - Mixer control.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",695
	;[696] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",696
	;[697] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",697
	;[698] REM - Internal channel: PSG_MIXER
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",698
	;[699] REM - ECS channel: PSG_ECS_MIXER
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",699
	;[700] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",700
	;[701] CONST PSG_TONE_CHANNELA_DISABLE		= $01	' Disable channel A tone.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",701
	;[702] CONST PSG_TONE_CHANNELB_DISABLE		= $02	' Disable channel B tone.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",702
	;[703] CONST PSG_TONE_CHANNELC_DISABLE		= $04	' Disable channel C tone.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",703
	;[704] CONST PSG_NOISE_CHANNELA_DISABLE	= $08	' Disable channel A noise.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",704
	;[705] CONST PSG_NOISE_CHANNELB_DISABLE	= $10	' Disable channel B noise.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",705
	;[706] CONST PSG_NOISE_CHANNELC_DISABLE	= $20	' Disable channel C noise.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",706
	;[707] CONST PSG_MIXER_DEFAULT				= $38 	' All notes enabled. all noise disabled.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",707
	;[708] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",708
	;[709] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",709
	;[710] REM PSG - Envelope control.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",710
	;[711] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",711
	;[712] REM Notes:
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",712
	;[713] REM - Internal channel: PSG_ENVELOPE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",713
	;[714] REM - ECS channel: PSG_ECS_ENVELOPE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",714
	;[715] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",715
	;[716] CONST PSG_ENVELOPE_HOLD								= $01
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",716
	;[717] CONST PSG_ENVELOPE_ALTERNATE						= $02
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",717
	;[718] CONST PSG_ENVELOPE_ATTACK							= $04
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",718
	;[719] CONST PSG_ENVELOPE_CONTINUE							= $08
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",719
	;[720] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_OFF	= $00 '\______
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",720
	;[721] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_OFF		= $04 '/______
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",721
	;[724] CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_SAWTOOTH			= $08 '\\\\\\CONST PSG_ENVELOPE_CYCLE_RAMP_DOWN_TRIANGLE			= $0A '\/\/\/CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_DOWN_AND_MAX	= $0B '\^^^^^^
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",724
	;[725] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_SAWTOOTH			= $0C '///////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",725
	;[726] CONST PSG_ENVELOPE_SINGLE_SHOT_RAMP_UP_AND_MAX		= $0D '/^^^^^^
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",726
	;[727] CONST PSG_ENVELOPE_CYCLE_RAMP_UP_TRIANGLE			= $0E '/\/\/\/
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",727
	;[728] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",728
	;[729] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",729
	;[730] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",730
	;[731] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",731
	;[732] REM Useful functions.
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",732
	;[733] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",733
	;[734] DEF FN screenpos(aColumn, aRow)				=               (((aRow)*BACKGROUND_COLUMNS)+(aColumn))
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",734
	;[735] DEF FN screenaddr(aColumn, aRow)			= (BACKTAB_ADDR+(((aRow)*BACKGROUND_COLUMNS)+(aColumn)))
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",735
	;[736] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",736
	;[737] DEF FN setspritex(aSpriteNo,anXPosition)	= #mobshadow(aSpriteNo  )=(#mobshadow(aSpriteNo  ) and $ff00)+anXPosition
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",737
	;[738] DEF FN setspritey(aSpriteNo,aYPosition)		= #mobshadow(aSpriteNo+8)=(#mobshadow(aSpriteNo+8) and $ff80)+aYPosition
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",738
	;[739] DEF FN resetsprite(aSpriteNo)				= sprite aSpriteNo, 0, 0, 0
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",739
	;[740] DEF FN togglespritevisible(aSpriteNo)		= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor VISIBLE
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",740
	;[741] DEF FN togglespritehit(aSpriteNo)			= #mobshadow(aSpriteNo   )=#mobshadow(aSpriteNo)    xor HIT
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",741
	;[742] DEF FN togglespritebehind(aSpriteNo)		= #mobshadow(aSpriteNo+16)=#mobshadow(aSpriteNo+16) xor BEHIND
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",742
	;[743] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",743
	;[744] REM /////////////////////////////////////////////////////////////////////////
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",744
	;[745] 
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",745
	;[746] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",746
	;[747] REM END
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",747
	;[748] REM -------------------------------------------------------------------------
	SRCFILE "C:\Users\Josue\OneDrive\Software\IntyBASIC SDK\lib\constants.bas",748
	;ENDFILE
	;FILE C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS
	;[20] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",20
	;[21] CONST CARD_WIDTH = 8		' Width of a background card, in pixels
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",21
	;[22] CONST CARD_HEIGHT = 8		' Height of a background card, in pixels
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",22
	;[23] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",23
	;[24] dim objectX(3), objectY(3), object(3) 'objectX keeps track of which lanes the object is using the card location, objectY keeps track of the y position for animation, object keeps track of the object in each lane
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",24
	;[25] dim #objectColor(4)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",25
	;[26] ' 0 = nothing
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",26
	;[27] ' 1 = rock
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",27
	;[28] ' 2 = coin
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",28
	;[29] ' 3 = apple (extra live)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",29
	;[30] ' 4 - 6 = power up
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",30
	;[31] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",31
	;[32] #objectColor(0) = SPR_GREEN '^^^^ colors for object ^^^^
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",32
	MVII #5,R0
	MVO R0,Q6
	;[33] #objectColor(1) = SPR_GREY
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",33
	MVII #4096,R0
	MVO R0,Q6+1
	;[34] #objectColor(2) = SPR_YELLOW
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",34
	MVII #6,R0
	MVO R0,Q6+2
	;[35] #objectColor(3) = SPR_RED
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",35
	MVII #2,R0
	MVO R0,Q6+3
	;[36] #objectColor(4) = SPR_BLUE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",36
	MVII #1,R0
	MVO R0,Q6+4
	;[37] #objectColor(5) = SPR_BLACK
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",37
	CLRR R0
	MVO R0,Q6+5
	;[38] #objectColor(6) = SPR_GREEN
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",38
	MVII #5,R0
	MVO R0,Q6+6
	;[39] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",39
	;[40] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",40
	;[41] objectX(0) = 4 'range 0 - 19
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",41
	MVII #4,R0
	MVO R0,Q3
	;[42] objectX(1) = 7
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",42
	MVII #7,R0
	MVO R0,Q3+1
	;[43] objectX(2) = 9
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",43
	MVII #9,R0
	MVO R0,Q3+2
	;[44] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",44
	;[45] for a = 0 to 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",45
	CLRR R0
	MVO R0,V1
T1:
	;[46]     objectY(a) = random(3)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",46
	MVII #3,R1
	CALL _next_random
	CALL qs_mpy8
	SWAP R0
	ANDI #255,R0
	MVII #Q4,R3
	ADD V1,R3
	MVO@ R0,R3
	;[47] 	object(a) = 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",47
	MVII #2,R0
	ADDI #(Q5-Q4) AND $FFFF,R3
	MVO@ R0,R3
	;[48] next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",48
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #2,R0
	BLE T1
	;[49] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",49
	;[50] playerX = random(3)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",50
	MVII #3,R1
	CALL _next_random
	CALL qs_mpy8
	SWAP R0
	ANDI #255,R0
	MVO R0,V2
	;[51] #playerColor = SPR_RED 'color of character
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",51
	MVII #2,R0
	MVO R0,V3
	;[52] playerDX = 1 'rate of frame change
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",52
	MVII #1,R0
	MVO R0,V4
	;[53] playerY = 10 'player y  position
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",53
	MVII #10,R0
	MVO R0,V5
	;[54] playerF = 2	'player first frame
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",54
	MVII #2,R0
	MVO R0,V6
	;[55] invisible = 0 'activation of power ups
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",55
	CLRR R0
	MVO R0,V7
	;[56] bonus_exp = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",56
	MVO R0,V8
	;[57] bonus_lives = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",57
	NOP
	MVO R0,V9
	;[58] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",58
	;[59] chance = 0 'used to determinate which object to show
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",59
	MVO R0,V10
	;[60] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",60
	;[61] 'Level ajustament
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",61
	;[62] dificulty = 1 'level's dificulty
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",62
	MVII #1,R0
	MVO R0,V11
	;[63] #maximunScore = 100 'level's score to pass it
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",63
	MVII #100,R0
	MVO R0,V12
	;[64] dim percentage(4) 'keep track of the likelihood of an object appearing
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",64
	;[65] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",65
	;[66] const highestDifficulty = 7 'highest dificulty possible
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",66
	;[67] scene = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",67
	CLRR R0
	MVO R0,V13
	;[68] jump = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",68
	MVO R0,V14
	;[69] #score = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",69
	NOP
	MVO R0,V15
	;[70] heartrate = 0 'animation for heart
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",70
	MVO R0,V16
	;[71] lives = 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",71
	MVII #3,R0
	MVO R0,V17
	;[72] level = 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",72
	MVII #1,R0
	MVO R0,V18
	;[73] univclock=0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",73
	CLRR R0
	MVO R0,V19
	;[74] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",74
	;[75] street_lineY = 0 'road lines tracking
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",75
	MVO R0,V20
	;[76] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",76
	;[77] 'MODE   SCREEN_COLOR_STACK, STACK_GREEN, STACK_BLACK, STACK_GREEN, STACK_BLACK
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",77
	;[78] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",78
	;[79] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",79
	CALL _wait
	;[80] DEFINE 0,16,screen_bitmaps_0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",80
	CLRR R0
	MVO R0,_gram_target
	MVII #16,R0
	MVO R0,_gram_total
	MVII #Q8,R0
	MVO R0,_gram_bitmap
	;[81] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",81
	CALL _wait
	;[82] DEFINE 16,16,screen_bitmaps_1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",82
	MVII #16,R0
	MVO R0,_gram_target
	MVO R0,_gram_total
	MVII #Q9,R0
	MVO R0,_gram_bitmap
	;[83] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",83
	CALL _wait
	;[84] DEFINE 32,16,screen_bitmaps_2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",84
	MVII #32,R0
	MVO R0,_gram_target
	MVII #16,R0
	MVO R0,_gram_total
	MVII #Q10,R0
	MVO R0,_gram_bitmap
	;[85] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",85
	CALL _wait
	;[86] DEFINE 48,4,screen_bitmaps_3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",86
	MVII #48,R0
	MVO R0,_gram_target
	MVII #4,R0
	MVO R0,_gram_total
	MVII #Q11,R0
	MVO R0,_gram_bitmap
	;[87] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",87
	CALL _wait
	;[88] define 52,5, player
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",88
	MVII #52,R0
	MVO R0,_gram_target
	MVII #5,R0
	MVO R0,_gram_total
	MVII #Q12,R0
	MVO R0,_gram_bitmap
	;[89] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",89
	CALL _wait
	;[90] define 57,2, tiles
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",90
	MVII #57,R0
	MVO R0,_gram_target
	MVII #2,R0
	MVO R0,_gram_total
	MVII #Q13,R0
	MVO R0,_gram_bitmap
	;[91] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",91
	CALL _wait
	;[92] define 59,3, street
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",92
	MVII #59,R0
	MVO R0,_gram_target
	MVII #3,R0
	MVO R0,_gram_total
	MVII #Q14,R0
	MVO R0,_gram_bitmap
	;[93] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",93
	CALL _wait
	;[94] define 62,1, nothing
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",94
	MVII #62,R0
	MVO R0,_gram_target
	MVII #1,R0
	MVO R0,_gram_total
	MVII #Q15,R0
	MVO R0,_gram_bitmap
	;[95] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",95
	CALL _wait
	;[96] define 63,1, rock
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",96
	MVII #63,R0
	MVO R0,_gram_target
	MVII #1,R0
	MVO R0,_gram_total
	MVII #Q16,R0
	MVO R0,_gram_bitmap
	;[97] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",97
	CALL _wait
	;[98] define 64,1, coin
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",98
	MVII #64,R0
	MVO R0,_gram_target
	MVII #1,R0
	MVO R0,_gram_total
	MVII #Q17,R0
	MVO R0,_gram_bitmap
	;[99] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",99
	CALL _wait
	;[100] define 65,1, apple
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",100
	MVII #65,R0
	MVO R0,_gram_target
	MVII #1,R0
	MVO R0,_gram_total
	MVII #Q18,R0
	MVO R0,_gram_bitmap
	;[101] wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",101
	CALL _wait
	;[102] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",102
	;[103] DEF FN SpritePosX(aColumn, anOffset) = ((aColumn + 1) * CARD_WIDTH ) + anOffset 'allows for the sprite to be used in a similar way to print at
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",103
	;[104] DEF FN SpritePosY(aRow, anOffset) = ((aRow    + 1) * CARD_HEIGHT) + anOffset
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",104
	;[105] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",105
	;[106] cls
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",106
	CALL CLRSCR
	;[107] main:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",107
	; MAIN
Q19:	;[108] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",108
	;[109] 	IF scene = 0 THEN GOSUB scene1 'intro
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",109
	MVI V13,R0
	TSTR R0
	BNE T2
	CALL Q20
T2:
	;[110] 	IF scene = 1 THEN GOSUB scene2 'game
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",110
	MVI V13,R0
	CMPI #1,R0
	BNE T3
	CALL Q21
T3:
	;[111] 	IF scene = 2 THEN GOSUB scene3 'end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",111
	MVI V13,R0
	CMPI #2,R0
	BNE T4
	CALL Q22
T4:
	;[112] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",112
	;[113] 	univclock = (univclock + 1) % 128 'used for animation and control over how offen something show up
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",113
	MVI V19,R0
	INCR R0
	ANDI #127,R0
	MVO R0,V19
	;[114] goto main
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",114
	B Q19
	;[115] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",115
	;[116] scene1: procedure 'Introduction
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",116
	; SCENE1
Q20:	PROC
	BEGIN
	;[117] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",117
	CALL _wait
	;[118] 	print at SCREENPOS(1, 0) color CS_WHITE,"- RunnerZ"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",118
	MVII #513,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #104,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #400,R0
	MVO@ R0,R4
	XORI #824,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #832,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[119] 	print at SCREENPOS(1, 1) color CS_WHITE,"- v1.1"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",119
	MVII #533,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #104,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #688,R0
	MVO@ R0,R4
	XORI #568,R0
	MVO@ R0,R4
	XORI #248,R0
	MVO@ R0,R4
	XORI #248,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[120] 	print at SCREENPOS(1, 2) color CS_WHITE,"- Made by: Josue"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",120
	MVII #553,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #104,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #360,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #528,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #536,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #336,R0
	MVO@ R0,R4
	XORI #808,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #128,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[121] 	print at SCREENPOS(1, 3) color CS_WHITE,"- Github: JosueCom"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",121
	MVII #573,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #104,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #312,R0
	MVO@ R0,R4
	XORI #880,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #704,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #336,R0
	MVO@ R0,R4
	XORI #808,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #128,R0
	MVO@ R0,R4
	XORI #816,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #16,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[122] 	print at SCREENPOS(0, 10) color CS_WHITE, "'Right' to continue"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",122
	MVII #712,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #56,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #672,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #632,R0
	MVO@ R0,R4
	XORI #536,R0
	MVO@ R0,R4
	XORI #96,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #128,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[123] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",123
	;[124] 	if univclock%8 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'frame to show during animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",124
	MVI V19,R0
	ANDI #7,R0
	BNE T5
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T6
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T8
T7:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T7
T8:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T6:
T5:
	;[125] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",125
	;[126] 	SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(5, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",126
	MVII #1616,R0
	MVO R0,_mobs
	MVII #816,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2466,R0
	MVO R0,_mobs+16
	;[127] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",127
	;[128] 	if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," " ' right arrow animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",128
	MVI V16,R0
	TSTR R0
	BEQ T9
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	B T10
T9:
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T10:
	;[129] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",129
	;[130] 	IF cont1.right THEN scene = 1: mode 1 : gosub levelupAnimation 'go to game once pressed
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",130
	MVI 511,R0
	COMR R0
	ANDI #2,R0
	BEQ T11
	MVII #1,R0
	MVO R0,V13
	MVII #3,R0
	MVO R0,_mode_select
	CALL Q24
T11:
	;[131] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",131
	RETURN
	;[132] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",132
	;[133] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",133
	ENDP
	;[134] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",134
	;[135] scene2: procedure
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",135
	; SCENE2
Q21:	PROC
	BEGIN
	;[136] 	SCREEN screen_cards 'draw background
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",136
	MVII #Q26,R3
	MVII #512,R2
	MVII #20,R1
	MVII #12,R0
	CALL CPYBLK
	;[137] 	gosub determinelevel 'determinate properties of the current level
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",137
	CALL Q27
	;[138] 	gosub background 'draw extra things in the background such as score and lives
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",138
	CALL Q28
	;[139] 	gosub drawObjects 'draw object and determinate their properties and behavior
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",139
	CALL Q29
	;[140] 	gosub drawPlayer  'draw player and determinate his behavior
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",140
	CALL Q30
	;[141] 	'IF FRAME AND 1 THEN GOSUB move_player
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",141
	;[142] 	'IF FRAME AND 1 THEN GOSUB enemy
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",142
	;[143] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",143
	;[144] 	if lives <= 0 then gosub clearAll : gosub clearPower : scene = 2 'if their is not more lives go to the end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",144
	MVI V17,R0
	CMPI #0,R0
	BGT T12
	CALL Q31
	CALL Q32
	MVII #2,R0
	MVO R0,V13
T12:
	;[145] 	if lives > 99 then lives = 10 : invisible = 100 'if lives if greater than what the screen can show give it 10 lives and the power up invisible for a long period
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",145
	MVI V17,R0
	CMPI #99,R0
	BLE T13
	MVII #10,R0
	MVO R0,V17
	MVII #100,R0
	MVO R0,V7
T13:
	;[146] 	if #score >= #maximunScore then level = level + 1 : gosub clearPower : #score = 0 : gosub levelupAnimation 'if score obtained, move to the next level
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",146
	MVI V15,R0
	CMP V12,R0
	BLT T14
	MVI V18,R0
	INCR R0
	MVO R0,V18
	CALL Q32
	CLRR R0
	MVO R0,V15
	CALL Q24
T14:
	;[147] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",147
	;[148] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",148
	CALL _wait
	;[149] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",149
	RETURN
	;[150] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",150
	ENDP
	;[151] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",151
	;[152] scene3: procedure 'End scene
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",152
	; SCENE3
Q22:	PROC
	BEGIN
	;[153] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",153
	;[154] 	MODE   SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",154
	MVII #20480,R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[155] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",155
	CALL _wait
	;[156] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",156
	;[157] 	print at SCREENPOS(2, 2) color CS_BLUE,"Made by: Josue"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",157
	MVII #554,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #360,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #40,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #552,R0
	MVO@ R0,R4
	XORI #528,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #536,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #336,R0
	MVO@ R0,R4
	XORI #808,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #128,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[158] 	print at SCREENPOS(2, 3) color CS_WHITE,"Press 'Right' To:"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",158
	MVII #574,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #680,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[159] 	print at SCREENPOS(2, 4) color CS_WHITE,"> Play Again"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",159
	MVII #594,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #240,R0
	MVO@ R0,R4
	XORI #384,R0
	MVO@ R0,R4
	XORI #992,R0
	MVO@ R0,R4
	XORI #104,R0
	MVO@ R0,R4
	XORI #192,R0
	MVO@ R0,R4
	XORI #712,R0
	MVO@ R0,R4
	XORI #264,R0
	MVO@ R0,R4
	XORI #816,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #64,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[160] 	print at SCREENPOS(2, 5) color CS_WHITE,"Press 'Left' To:"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",160
	MVII #614,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #344,R0
	MVO@ R0,R4
	XORI #840,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #680,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[161] 	print at SCREENPOS(2, 6) color CS_WHITE,"> Quit"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",161
	MVII #634,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #240,R0
	MVO@ R0,R4
	XORI #392,R0
	MVO@ R0,R4
	XORI #800,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[162] 	if univclock%15 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",162
	MVI V19,R0
T16:
	SUBI #15,R0
	BC T16
	ADDI #15,R0
	BNE T15
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T17
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T19
T18:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T18
T19:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T17:
T15:
	;[163] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",163
	;[164] 	SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(7, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",164
	MVII #1616,R0
	MVO R0,_mobs
	MVII #832,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2466,R0
	MVO R0,_mobs+16
	;[165] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",165
	;[166] 	'play again or end the game
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",166
	;[167] 	if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," "
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",167
	MVI V16,R0
	TSTR R0
	BEQ T20
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	B T21
T20:
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T21:
	;[168] 	if heartrate then print at SCREENPOS(0, 11) color CS_WHITE,"<" else print at SCREENPOS(0, 11) color CS_WHITE," "
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",168
	MVI V16,R0
	TSTR R0
	BEQ T22
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #224,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	B T23
T22:
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T23:
	;[169] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",169
	;[170] 	wait 'allow for time for the player to not miss press the button
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",170
	CALL _wait
	;[171] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",171
	CALL _wait
	;[172] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",172
	CALL _wait
	;[173] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",173
	CALL _wait
	;[174] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",174
	CALL _wait
	;[175] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",175
	CALL _wait
	;[176] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",176
	;[177] 	'reset everything with the right and game to the left
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",177
	;[178] 	if cont1.right then gosub clearAll : #score = 0 : lives = 3 : scene = 0 : level = 1 : wait : wait : wait : wait : wait : wait : wait : wait : wait : wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",178
	MVI 511,R0
	COMR R0
	ANDI #2,R0
	BEQ T24
	CALL Q31
	CLRR R0
	MVO R0,V15
	MVII #3,R0
	MVO R0,V17
	CLRR R0
	MVO R0,V13
	MVII #1,R0
	MVO R0,V18
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
T24:
	;[179] 	if cont1.left then gosub clearAll :goto end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",179
	MVI 511,R0
	COMR R0
	ANDI #8,R0
	BEQ T25
	CALL Q31
	B Q34
T25:
	;[180] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",180
	;[181] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",181
	RETURN
	ENDP
	;[182] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",182
	;[183] background: procedure 'draw and writes extra details to background such as score and lives 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",183
	; BACKGROUND
Q28:	PROC
	BEGIN
	;[184] 	if (univclock % 4) = 0 then street_lineY = (street_lineY + 1) % 7
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",184
	MVI V19,R0
	ANDI #3,R0
	BNE T26
	MVI V20,R0
	INCR R0
T27:
	SUBI #7,R0
	BC T27
	ADDI #7,R0
	MVO R0,V20
T26:
	;[185] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",185
	;[186] 	SPRITE 5, SpritePosX(4 - street_lineY/2, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR59 + SPR_GREY 'draw lines in lanes
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",186
	MVII #4,R0
	MVI V20,R1
	SLR R1,1
	SUBR R1,R0
	INCR R0
	SLL R0,2
	ADDR R0,R0
	ADDI #512,R0
	MVO R0,_mobs+5
	MVI V20,R0
	ADDI #6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #256,R0
	MVO R0,_mobs+13
	MVII #6616,R0
	MVO R0,_mobs+21
	;[187] 	SPRITE 6, SpritePosX(7, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR60 + SPR_GREY
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",187
	MVII #576,R0
	MVO R0,_mobs+6
	MVI V20,R0
	ADDI #6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #256,R0
	MVO R0,_mobs+14
	MVII #6624,R0
	MVO R0,_mobs+22
	;[188] 	SPRITE 7, SpritePosX(9 + street_lineY/2, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR61 + SPR_GREY
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",188
	MVI V20,R0
	SLR R0,1
	ADDI #10,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #512,R0
	MVO R0,_mobs+7
	MVI V20,R0
	ADDI #6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #256,R0
	MVO R0,_mobs+15
	MVII #6632,R0
	MVO R0,_mobs+23
	;[189] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",189
	;[190] 	gosub writescore 'write score
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",190
	CALL Q36
	;[191] 	gosub drawheart  'draw heart and nothing of lives
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",191
	CALL Q37
	;[192] 	gosub writelevel 'write the current level
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",192
	CALL Q38
	;[193] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",193
	;[194] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",194
	RETURN
	;[195] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",195
	ENDP
	;[196] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",196
	;[197] drawObjects: procedure
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",197
	; DRAWOBJECTS
Q29:	PROC
	BEGIN
	;[198] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",198
	;[199] 	for a = 0 to 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",199
	CLRR R0
	MVO R0,V1
T28:
	;[200] 		if (univclock % (highestDifficulty-dificulty)) = 0 then 'objects move at different rate depending on the dificulty
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",200
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T30
T31:
	SUBR R1,R0
	BC T31
	ADDR R1,R0
T30:
	TSTR R0
	BNE T29
	;[201] 			objectY(a) = (objectY(a) + 1) % 8
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",201
	MVII #Q4,R3
	ADD V1,R3
	MVI@ R3,R0
	INCR R0
	ANDI #7,R0
	MVO@ R0,R3
	;[202] 			if objectY(a) = 0 then gosub chooseObject : object(a) = chance
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",202
	MVI@ R3,R0
	TSTR R0
	BNE T32
	CALL Q40
	MVI V10,R0
	MVII #Q5,R3
	ADD V1,R3
	MVO@ R0,R3
T32:
	;[203] 		end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",203
T29:
	;[204] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",204
	;[205] 	next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",205
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #2,R0
	BLE T28
	;[206] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",206
	;[207] 	objectX(0) = 4 - objectY(0)/2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",207
	MVII #4,R0
	MVI Q4,R1
	SLR R1,1
	SUBR R1,R0
	MVO R0,Q3
	;[208] 	objectX(2) = 9 + objectY(2)/2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",208
	MVI Q4+2,R0
	SLR R0,1
	ADDI #9,R0
	MVO R0,Q3+2
	;[209] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",209
	;[210] 	for a = 1 to 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",210
	MVII #1,R0
	MVO R0,V1
T33:
	;[211] 		if object(a - 1) >= 4 then 'if statement to see if power up has appear; draw different color for power ups
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",211
	MVII #Q5-1,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #4,R0
	BLT T34
	;[212] 			SPRITE a, SpritePosX(objectX(a - 1), 0) + VISIBLE, SpritePosY(4 + objectY(a - 1), 0) + ZOOMY2, SPR62 + (object(a - 1) - 3)* 8 + #objectColor(object(a - 1))
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",212
	MVII #Q1,R0
	ADD V1,R0
	MOVR R0,R4
	ADDI #(Q3-Q5) AND $FFFF,R3
	MVI@ R3,R0
	INCR R0
	SLL R0,2
	ADDR R0,R0
	ADDI #512,R0
	MVO@ R0,R4
	ADDI #(Q4-Q3) AND $FFFF,R3
	MVI@ R3,R0
	ADDI #5,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #256,R0
	ADDI #7,R4
	MVO@ R0,R4
	ADDI #(Q5-Q4) AND $FFFF,R3
	MVI@ R3,R0
	SUBI #3,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2544,R0
	MVII #Q6,R1
	ADD@ R3,R1
	ADD@ R1,R0
	ADDI #7,R4
	MVO@ R0,R4
	;[213] 			'if object(a - 1) = 4 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\319"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",213
	;[214] 			'if object(a - 1) = 5 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\320"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",214
	;[215] 			'if object(a - 1) = 6 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\321"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",215
	;[216] 		else 'if there is not power ups
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",216
	B T35
T34:
	;[217] 			SPRITE a, SpritePosX(objectX(a - 1), 0) + VISIBLE, SpritePosY(4 + objectY(a - 1), 0) + ZOOMY2, SPR62 + object(a - 1) * 8 + #objectColor(object(a - 1))
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",217
	MVII #Q1,R0
	ADD V1,R0
	MOVR R0,R4
	MVII #Q3-1,R3
	ADD V1,R3
	MVI@ R3,R0
	INCR R0
	SLL R0,2
	ADDR R0,R0
	ADDI #512,R0
	MVO@ R0,R4
	ADDI #(Q4-Q3) AND $FFFF,R3
	MVI@ R3,R0
	ADDI #5,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #256,R0
	ADDI #7,R4
	MVO@ R0,R4
	ADDI #(Q5-Q4) AND $FFFF,R3
	MVI@ R3,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2544,R0
	MVII #Q6,R1
	ADD@ R3,R1
	ADD@ R1,R0
	ADDI #7,R4
	MVO@ R0,R4
	;[218] 		end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",218
T35:
	;[219] 	next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",219
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #3,R0
	BLE T33
	;[220] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",220
	;[221] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",221
	RETURN
	;[222] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",222
	ENDP
	;[223] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",223
	;[224] drawPlayer: procedure 'collision with the player and player's behavior
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",224
	; DRAWPLAYER
Q30:	PROC
	BEGIN
	;[225] 	if cont1.left AND univclock%5 = 0 then playerX = playerX - 1 'various commands: move right, move left, jump, pause
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",225
	MVI 511,R0
	COMR R0
	ANDI #8,R0
	MVI V19,R1
T37:
	SUBI #5,R1
	BC T37
	ADDI #5,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T36
	MVI V2,R0
	DECR R0
	MVO R0,V2
T36:
	;[226] 	if cont1.right AND univclock%5 = 0 then playerX = playerX + 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",226
	MVI 511,R0
	COMR R0
	ANDI #2,R0
	MVI V19,R1
T39:
	SUBI #5,R1
	BC T39
	ADDI #5,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T38
	MVI V2,R0
	INCR R0
	MVO R0,V2
T38:
	;[227] 	if cont1.up AND univclock%5 = 0 AND playerY = 10 then jump = 5
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",227
	MVI 511,R0
	COMR R0
	ANDI #4,R0
	MVI V19,R1
T41:
	SUBI #5,R1
	BC T41
	ADDI #5,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	MVI V5,R1
	CMPI #10,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T40
	MVII #5,R0
	MVO R0,V14
T40:
	;[228] 	if cont1.B0 AND univclock%5 = 0 then gosub pauseScene
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",228
	MVI 511,R0
	COMR R0
	ANDI #224,R0
	CMPI #160,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V19,R1
T43:
	SUBI #5,R1
	BC T43
	ADDI #5,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T42
	CALL Q42
T42:
	;[229] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",229
	;[230] 	playerX = (playerX + 3) % 3 'keep player within the three lanes: 0 = lane 1, 1 = lane 2, 2 = lane 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",230
	MVI V2,R0
	ADDI #3,R0
T44:
	SUBI #3,R0
	BC T44
	ADDI #3,R0
	MVO R0,V2
	;[231] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",231
	;[232] 	if univclock%(highestDifficulty-dificulty) = 0 AND jump > 0 then playerY = 10 - jump + 2: jump = jump - 1 : playerF = 3 'check to see if condition for power ups and jump have been met
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",232
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T46
T47:
	SUBR R1,R0
	BC T47
	ADDR R1,R0
T46:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V14,R1
	CMPI #0,R1
	MVII #-1,R1
	BGT $+3
	INCR R1
	ANDR R1,R0
	BEQ T45
	MVII #10,R0
	SUB V14,R0
	ADDI #2,R0
	MVO R0,V5
	MVI V14,R0
	DECR R0
	MVO R0,V14
	MVII #3,R0
	MVO R0,V6
T45:
	;[233] 	if univclock%(highestDifficulty-dificulty) = 0 AND invisible > 0 then playerY = 8: invisible = invisible - 1 : playerF = 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",233
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T49
T50:
	SUBR R1,R0
	BC T50
	ADDR R1,R0
T49:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	CMPI #0,R1
	MVII #-1,R1
	BGT $+3
	INCR R1
	ANDR R1,R0
	BEQ T48
	MVII #8,R0
	MVO R0,V5
	MVI V7,R0
	DECR R0
	MVO R0,V7
	MVII #3,R0
	MVO R0,V6
T48:
	;[234] 	if univclock%(highestDifficulty-dificulty) = 0 AND bonus_lives > 0 then gosub add_lives : bonus_lives = bonus_lives - 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",234
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T52
T53:
	SUBR R1,R0
	BC T53
	ADDR R1,R0
T52:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V9,R1
	CMPI #0,R1
	MVII #-1,R1
	BGT $+3
	INCR R1
	ANDR R1,R0
	BEQ T51
	CALL Q43
	MVI V9,R0
	DECR R0
	MVO R0,V9
T51:
	;[235] 	if univclock%(highestDifficulty-dificulty) = 0 AND bonus_exp > 0 then gosub add_points : bonus_exp = bonus_exp - 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",235
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T55
T56:
	SUBR R1,R0
	BC T56
	ADDR R1,R0
T55:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V8,R1
	CMPI #0,R1
	MVII #-1,R1
	BGT $+3
	INCR R1
	ANDR R1,R0
	BEQ T54
	CALL Q44
	MVI V8,R0
	DECR R0
	MVO R0,V8
T54:
	;[236] 	if univclock%(highestDifficulty-dificulty) = 0 AND jump = 0 AND invisible = 0 then playerY = 10: playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",236
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T58
T59:
	SUBR R1,R0
	BC T59
	ADDR R1,R0
T58:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V14,R1
	TSTR R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	MVI V7,R1
	TSTR R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T57
	MVII #10,R0
	MVO R0,V5
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T60
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T62
T61:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T61
T62:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T60:
T57:
	;[237] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",237
	;[238] 	if invisible > 0 then 'different color based on the power up
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",238
	MVI V7,R0
	CMPI #0,R0
	BLE T63
	;[239] 		#playerColor = SPR_BLUE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",239
	MVII #1,R0
	MVO R0,V3
	;[240] 	elseif bonus_lives > 0 then
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",240
	B T64
T63:
	MVI V9,R0
	CMPI #0,R0
	BLE T65
	;[241] 		#playerColor = SPR_GREEN
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",241
	MVII #5,R0
	MVO R0,V3
	;[242] 	elseif bonus_exp > 0 then
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",242
	B T64
T65:
	MVI V8,R0
	CMPI #0,R0
	BLE T66
	;[243] 		#playerColor = SPR_BLACK
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",243
	CLRR R0
	MVO R0,V3
	;[244] 	else 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",244
	B T64
T66:
	;[245] 		#playerColor = SPR_RED
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",245
	MVII #2,R0
	MVO R0,V3
	;[246] 	end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",246
T64:
	;[247] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",247
	;[248] 	SPRITE 0, SpritePosX(2 + 4 * playerX, 0) + VISIBLE + ZOOMX2, SpritePosY(playerY, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + #playerColor 'draw player
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",248
	MVI V2,R0
	SLL R0,2
	ADDI #3,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #1536,R0
	MVO R0,_mobs
	MVI V5,R0
	INCR R0
	SLL R0,2
	ADDR R0,R0
	ADDI #768,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2464,R0
	ADD V3,R0
	MVO R0,_mobs+16
	;[249] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",249
	;[250] 	for a = 0 to 2 'check all three lanes for collision
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",250
	CLRR R0
	MVO R0,V1
T67:
	;[251] 		if (univclock%(highestDifficulty-dificulty) = 0 AND 4 + objectY(a) = playerY AND objectX(playerX) = objectX(a) AND jump = 0)then 'detects collision with objects
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",251
	MVI V19,R0
	MVII #7,R1
	SUB V11,R1
	BEQ T69
T70:
	SUBR R1,R0
	BC T70
	ADDR R1,R0
T69:
	TSTR R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVII #Q4,R3
	ADD V1,R3
	MVI@ R3,R1
	ADDI #4,R1
	CMP V5,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	MVII #Q3,R3
	ADD V2,R3
	MVI@ R3,R1
	MVII #Q3,R3
	ADD V1,R3
	CMP@ R3,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	MVI V14,R1
	TSTR R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T68
	;[252] 			if object(a) = 1 AND invisible = 0 then lives = lives - 1 : gosub lose_points  'different behavior for various objects
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",252
	ADDI #(Q5-Q3) AND $FFFF,R3
	MVI@ R3,R0
	CMPI #1,R0
	MVII #-1,R0
	BEQ $+3
	INCR R0
	MVI V7,R1
	TSTR R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T71
	MVI V17,R0
	DECR R0
	MVO R0,V17
	CALL Q45
T71:
	;[253] 			if object(a) = 2 then gosub add_points : gosub writescore
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",253
	MVII #Q5,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #2,R0
	BNE T72
	CALL Q44
	CALL Q36
T72:
	;[254] 			if object(a) = 3 then gosub add_points : #score = #score + 1 : lives = lives + 1 : gosub writescore : gosub drawheart
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",254
	MVII #Q5,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #3,R0
	BNE T73
	CALL Q44
	MVI V15,R0
	INCR R0
	MVO R0,V15
	MVI V17,R0
	INCR R0
	MVO R0,V17
	CALL Q36
	CALL Q37
T73:
	;[255] 			if object(a) = 4 then invisible = 35 : power = 4 : gosub powerupAnimation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",255
	MVII #Q5,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #4,R0
	BNE T74
	MVII #35,R0
	MVO R0,V7
	MVII #4,R0
	MVO R0,V21
	CALL Q46
T74:
	;[256] 			if object(a) = 5 then bonus_exp = 5 : power = 5 : gosub powerupAnimation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",256
	MVII #Q5,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #5,R0
	BNE T75
	MVII #5,R0
	MVO R0,V8
	MVO R0,V21
	CALL Q46
T75:
	;[257] 			if object(a) = 6 then gosub add_points : bonus_lives = 5 : power = 6 : gosub powerupAnimation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",257
	MVII #Q5,R3
	ADD V1,R3
	MVI@ R3,R0
	CMPI #6,R0
	BNE T76
	CALL Q44
	MVII #5,R0
	MVO R0,V9
	MVII #6,R0
	MVO R0,V21
	CALL Q46
T76:
	;[258] 		end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",258
T68:
	;[259] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",259
	;[260] 	next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",260
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #2,R0
	BLE T67
	;[261] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",261
	RETURN
	;[262] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",262
	ENDP
	;[263] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",263
	;[264] levelupAnimation: procedure 'animation when there is increase in level
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",264
	; LEVELUPANIMATION
Q24:	PROC
	BEGIN
	;[265] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",265
	CALL _wait
	;[266] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",266
	CALL Q31
	;[267] 	for a = 0 to 75
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",267
	CLRR R0
	MVO R0,V1
T77:
	;[268] 		if a%3 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",268
	MVI V1,R0
T79:
	SUBI #3,R0
	BC T79
	ADDI #3,R0
	BNE T78
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T80
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T82
T81:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T81
T82:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T80:
T78:
	;[269] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",269
	;[270] 		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(3, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'paint player red
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",270
	MVII #1616,R0
	MVO R0,_mobs
	MVII #800,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2466,R0
	MVO R0,_mobs+16
	;[271] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",271
	;[272] 		print at (SCREENPOS(7, 5)) color CS_RED, (level%10+16)*8+6 'print which level we are going to
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",272
	MVII #619,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V18,R0
T83:
	SUBI #10,R0
	BC T83
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[273] 		print at (SCREENPOS(12, 5)) color CS_RED, (level%10+16)*8+6
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",273
	MVII #624,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V18,R0
T84:
	SUBI #10,R0
	BC T84
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[274] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",274
	CALL _wait
	;[275] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",275
	CALL _wait
	;[276] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",276
	CALL _wait
	;[277] 	next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",277
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #75,R0
	BLE T77
	;[278] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",278
	CALL Q31
	;[279] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",279
	RETURN
	ENDP
	;[280] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",280
	;[281] powerupAnimation: procedure 'animation when there is a power up
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",281
	; POWERUPANIMATION
Q46:	PROC
	BEGIN
	;[282] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",282
	CALL _wait
	;[283] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",283
	CALL Q31
	;[284] 	MODE SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK 'need in order to use print at
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",284
	MVII #20480,R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[285] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",285
	CALL _wait
	;[286] 	for a = 0 to 75
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",286
	CLRR R0
	MVO R0,V1
T85:
	;[287] 		if a%3 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",287
	MVI V1,R0
T87:
	SUBI #3,R0
	BC T87
	ADDI #3,R0
	BNE T86
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T88
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T90
T89:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T89
T90:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T88:
T86:
	;[288] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",288
	;[289] 		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(3, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_BLUE 'paint player blue
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",289
	MVII #1616,R0
	MVO R0,_mobs
	MVII #800,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2465,R0
	MVO R0,_mobs+16
	;[290] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",290
	;[291] 		if power = 4 then print at (SCREENPOS(7, 5)) color CS_BLUE, "\319" : print at (SCREENPOS(12, 5)) color CS_BLUE, "\319" 'print which power we obtained
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",291
	MVI V21,R0
	CMPI #4,R0
	BNE T91
	MVII #619,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2552,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	MVII #624,R0
	MVO R0,_screen
	MVII #1,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2552,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
T91:
	;[292] 		if power = 5 then print at (SCREENPOS(7, 5)) color CS_WHITE, "\320" : print at (SCREENPOS(12, 5)) color CS_WHITE, "\320"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",292
	MVI V21,R0
	CMPI #5,R0
	BNE T92
	MVII #619,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2560,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	MVII #624,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2560,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
T92:
	;[293] 		if power = 6 then print at (SCREENPOS(7, 5)) color CS_GREEN, "\321" : print at (SCREENPOS(12, 5)) color CS_GREEN, "\321"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",293
	MVI V21,R0
	CMPI #6,R0
	BNE T93
	MVII #619,R0
	MVO R0,_screen
	MVII #5,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2568,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	MVII #624,R0
	MVO R0,_screen
	MVII #5,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #2568,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
T93:
	;[294] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",294
	;[295] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",295
	CALL _wait
	;[296] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",296
	CALL _wait
	;[297] 		wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",297
	CALL _wait
	;[298] 	next a
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",298
	MVI V1,R0
	INCR R0
	MVO R0,V1
	CMPI #75,R0
	BLE T85
	;[299] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",299
	CALL Q31
	;[300] 	mode 1 'need for SCREEN command
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",300
	MVII #3,R0
	MVO R0,_mode_select
	;[301] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",301
	CALL _wait
	;[302] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",302
	RETURN
	ENDP
	;[303] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",303
	;[304] 'Pause scene
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",304
	;[305] pauseScene: procedure 'animation for when the game is paused
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",305
	; PAUSESCENE
Q42:	PROC
	BEGIN
	;[306] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",306
	CALL _wait
	;[307] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",307
	CALL Q31
	;[308] 	MODE SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK 'need in order to use print at
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",308
	MVII #20480,R0
	MVO R0,_color
	MVII #2,R0
	MVO R0,_mode_select
	;[309] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",309
	CALL _wait
	;[310] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",310
	CALL _wait
	;[311] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",311
	CALL _wait
	;[312] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",312
	CALL _wait
	;[313] 	paused = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",313
	CLRR R0
	MVO R0,V22
	;[314] 	a = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",314
	MVO R0,V1
	;[315] 	while paused = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",315
T94:
	MVI V22,R0
	TSTR R0
	BNE T95
	;[316] 		print at SCREENPOS(4, 2) color CS_RED,"PAUSED"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",316
	MVII #556,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #136,R0
	MVO@ R0,R4
	XORI #160,R0
	MVO@ R0,R4
	XORI #48,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[317] 		print at SCREENPOS(2, 3) color CS_WHITE,"Press 'Right' To:"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",317
	MVII #574,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #424,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #112,R0
	MVO@ R0,R4
	XORI #120,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #680,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[318] 		print at SCREENPOS(2, 4) color CS_WHITE,"> Continue"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",318
	MVII #594,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #240,R0
	MVO@ R0,R4
	XORI #280,R0
	MVO@ R0,R4
	XORI #864,R0
	MVO@ R0,R4
	XORI #8,R0
	MVO@ R0,R4
	XORI #208,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #216,R0
	MVO@ R0,R4
	XORI #128,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[319] 		print at SCREENPOS(2, 5) color CS_WHITE,"Press 'Left' To:"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",319
	MVII #614,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #384,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #784,R0
	MVO@ R0,R4
	XORI #184,R0
	MVO@ R0,R4
	XORI #176,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #344,R0
	MVO@ R0,R4
	XORI #840,R0
	MVO@ R0,R4
	XORI #24,R0
	MVO@ R0,R4
	XORI #144,R0
	MVO@ R0,R4
	XORI #664,R0
	MVO@ R0,R4
	XORI #56,R0
	MVO@ R0,R4
	XORI #416,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #680,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[320] 		print at SCREENPOS(2, 6) color CS_WHITE,"> Quit"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",320
	MVII #634,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #240,R0
	MVO@ R0,R4
	XORI #392,R0
	MVO@ R0,R4
	XORI #800,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #232,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[321] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",321
	;[322] 		if a%40 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",322
	MVI V1,R0
T97:
	SUBI #40,R0
	BC T97
	ADDI #40,R0
	BNE T96
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
	MVI V6,R0
	ADD V4,R0
	MVO R0,V6
	MVI V6,R0
	CMPI #4,R0
	MVII #-1,R0
	BGE $+3
	INCR R0
	MVI V6,R1
	CMPI #0,R1
	MVII #-1,R1
	BLE $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T98
	MVI V4,R0
	MVII #65535,R5
	CLRR R4
	CLRC
	RRC R0,1
	BEQ T100
T99:
	BNC $+3
	ADDR R5,R4
	ADDR R5,R5
	SARC R0,1
	BNE T99
T100:
	BNC $+3
	ADDR R5,R4
	MOVR R4,R0
	MVO R0,V4
T98:
T96:
	;[323] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",323
	;[324] 		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(7, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",324
	MVII #1616,R0
	MVO R0,_mobs
	MVII #832,R0
	MVO R0,_mobs+8
	MVI V6,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #2466,R0
	MVO R0,_mobs+16
	;[325] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",325
	;[326] 		'arrows animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",326
	;[327] 		if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," "
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",327
	MVI V16,R0
	TSTR R0
	BEQ T101
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #240,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	B T102
T101:
	MVII #751,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T102:
	;[328] 		if heartrate then print at SCREENPOS(0, 11) color CS_WHITE,"<" else print at SCREENPOS(0, 11) color CS_WHITE," "
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",328
	MVI V16,R0
	TSTR R0
	BEQ T103
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #224,R0
	XOR _color,R0
	MVO@ R0,R4
	MVO R4,_screen
	B T104
T103:
	MVII #732,R0
	MVO R0,_screen
	MVII #7,R0
	MVO R0,_color
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
T104:
	;[329] 		
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",329
	;[330] 		if cont1.left then scene = 1 : paused = 1 : wait : wait : wait : wait : wait : wait : wait : wait : wait : wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",330
	MVI 511,R0
	COMR R0
	ANDI #8,R0
	BEQ T105
	MVII #1,R0
	MVO R0,V13
	MVO R0,V22
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
	CALL _wait
T105:
	;[331] 		if cont1.right OR cont1.B0 then paused = 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",331
	MVI 511,R0
	COMR R0
	ANDI #2,R0
	MVI 511,R1
	COMR R1
	ANDI #224,R1
	CMPI #160,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	COMR R1
	ANDR R1,R0
	COMR R1
	XORR R1,R0
	BEQ T106
	MVII #1,R0
	MVO R0,V22
T106:
	;[332] 		a = a + 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",332
	MVI V1,R0
	INCR R0
	MVO R0,V1
	;[333] 	wend
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",333
	B T94
T95:
	;[334] 	gosub clearAll
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",334
	CALL Q31
	;[335] 	mode 1 'need for SCREEN command
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",335
	MVII #3,R0
	MVO R0,_mode_select
	;[336] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",336
	CALL _wait
	;[337] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",337
	RETURN
	ENDP
	;[338] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",338
	;[339] writescore: procedure 'print the current score
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",339
	; WRITESCORE
Q36:	PROC
	BEGIN
	;[340] 	if #score < 0 then #score = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",340
	MVI V15,R0
	CMPI #0,R0
	BGE T107
	CLRR R0
	MVO R0,V15
T107:
	;[341] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",341
	;[342] 	print at (SCREENPOS(16, 2)) color CS_RED, (#score/100%10+16)*8+6 'first digit
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",342
	MVII #568,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V15,R0
	MVII #-1,R4
T108:
	INCR R4
	SUBI #100,R0
	BC T108
	MOVR R4,R0
T109:
	SUBI #10,R0
	BC T109
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[343] 	print at (SCREENPOS(17, 2)) color CS_RED,(#score/10%10+16)*8+6	 'second digit
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",343
	MVII #569,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V15,R0
	MVII #-1,R4
T110:
	INCR R4
	SUBI #10,R0
	BC T110
	MOVR R4,R0
T111:
	SUBI #10,R0
	BC T111
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[344] 	print at (SCREENPOS(18, 2)) color CS_RED,(#score%10+16)*8+6		 'third digit
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",344
	MVII #570,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V15,R0
T112:
	SUBI #10,R0
	BC T112
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[345] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",345
	;[346] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",346
	RETURN
	;[347] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",347
	ENDP
	;[348] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",348
	;[349] chooseObject: procedure 'pick object to put on the list that will appear in the game
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",349
	; CHOOSEOBJECT
Q40:	PROC
	BEGIN
	;[350] 	chance = RANDOM(256) 'percentage is based of 256, not 100
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",350
	CALL _next_random
	ANDI #255,R0
	MVO R0,V10
	;[351] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",351
	;[352] 	if chance < percentage(0) then 'nothing chances
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",352
	MVI V10,R0
	MVI Q7,R1
	CMPR R1,R0
	BGE T113
	;[353] 		chance = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",353
	CLRR R0
	MVO R0,V10
	;[354] 	elseif chance < percentage(1) then 'rock chances
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",354
	B T114
T113:
	MVI V10,R0
	MVI Q7+1,R1
	CMPR R1,R0
	BGE T115
	;[355] 		chance = 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",355
	MVII #1,R0
	MVO R0,V10
	;[356] 	elseif chance < percentage(2) then 'coin chances
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",356
	B T114
T115:
	MVI V10,R0
	MVI Q7+2,R1
	CMPR R1,R0
	BGE T116
	;[357] 		chance = 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",357
	MVII #2,R0
	MVO R0,V10
	;[358] 	elseif chance < percentage(3) then 'apple chances
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",358
	B T114
T116:
	MVI V10,R0
	MVI Q7+3,R1
	CMPR R1,R0
	BGE T117
	;[359] 		chance = 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",359
	MVII #3,R0
	MVO R0,V10
	;[360] 	else 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",360
	B T114
T117:
	;[361] 		chance = RANDOM(3) + 4 'Powerup
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",361
	MVII #3,R1
	CALL _next_random
	CALL qs_mpy8
	SWAP R0
	ANDI #255,R0
	ADDI #4,R0
	MVO R0,V10
	;[362] 	end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",362
T114:
	;[363] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",363
	;[364] 	if invisible > 0 AND a = 1 then chance = 2 'if invisible is activated, make the middle lane all gold
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",364
	MVI V7,R0
	CMPI #0,R0
	MVII #-1,R0
	BGT $+3
	INCR R0
	MVI V1,R1
	CMPI #1,R1
	MVII #-1,R1
	BEQ $+3
	INCR R1
	ANDR R1,R0
	BEQ T118
	MVII #2,R0
	MVO R0,V10
T118:
	;[365] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",365
	;[366] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",366
	RETURN
	;[367] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",367
	ENDP
	;[368] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",368
	;[369] drawheart: procedure 'writes the number lives left and the heart animation
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",369
	; DRAWHEART
Q37:	PROC
	BEGIN
	;[370] 	if univclock%7 = 0 then heartrate = (heartrate + 1) % 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",370
	MVI V19,R0
T120:
	SUBI #7,R0
	BC T120
	ADDI #7,R0
	BNE T119
	MVI V16,R0
	INCR R0
	ANDI #1,R0
	MVO R0,V16
T119:
	;[371] 	if heartrate then SPRITE 4, SpritePosX(16, 0) + VISIBLE, SpritePosY(5, 0) + ZOOMY2, SPR57 + #playerColor else SPRITE 4, SpritePosX(16, 0) + VISIBLE, SpritePosY(5, 0) + ZOOMY2, SPR58 + #playerColor
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",371
	MVI V16,R0
	TSTR R0
	BEQ T121
	MVII #648,R0
	MVO R0,_mobs+4
	MVII #304,R0
	MVO R0,_mobs+12
	MVII #2504,R0
	ADD V3,R0
	MVO R0,_mobs+20
	B T122
T121:
	MVII #648,R0
	MVO R0,_mobs+4
	MVII #304,R0
	MVO R0,_mobs+12
	MVII #2512,R0
	ADD V3,R0
	MVO R0,_mobs+20
T122:
	;[372] 	print at (SCREENPOS(17, 5)) color CS_RED,(lives/10%10+16)*8+6
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",372
	MVII #629,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V17,R0
	MVII #-1,R4
T123:
	INCR R4
	SUBI #10,R0
	BC T123
	MOVR R4,R0
T124:
	SUBI #10,R0
	BC T124
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[373] 	print at (SCREENPOS(18, 5)) color CS_RED,(lives%10+16)*8+6
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",373
	MVII #630,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V17,R0
T125:
	SUBI #10,R0
	BC T125
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[374] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",374
	RETURN
	;[375] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",375
	ENDP
	;[376] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",376
	;[377] writelevel: procedure 'writes the level at the bottom of the screen
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",377
	; WRITELEVEL
Q38:	PROC
	BEGIN
	;[378] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",378
	;[379] 	print at (SCREENPOS(17, 8)) color CS_RED, (level%10+16)*8+6
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",379
	MVII #689,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI V18,R0
T126:
	SUBI #10,R0
	BC T126
	ADDI #26,R0
	SLL R0,2
	ADDR R0,R0
	ADDI #6,R0
	MVI _screen,R4
	MVO@ R0,R4
	MVO R4,_screen
	;[380] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",380
	;[381] 	return
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",381
	RETURN
	;[382] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",382
	ENDP
	;[383] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",383
	;[384] determinelevel: procedure 'percentage is out of 256; likelihood of an object appearing go to line 25-28 to see what each percentage if for from the index
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",384
	; DETERMINELEVEL
Q27:	PROC
	BEGIN
	;[385] 	if(level = 1) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",385
	MVI V18,R0
	CMPI #1,R0
	BNE T127
	;[386] 		dificulty=1 'rate of object showing up
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",386
	MVII #1,R0
	MVO R0,V11
	;[387] 		#maximunScore = 100 'score needed to pass level
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",387
	MVII #100,R0
	MVO R0,V12
	;[388] 		percentage(0) = 51
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",388
	MVII #51,R0
	MVO R0,Q7
	;[389] 		percentage(1) = percentage(0) + 51
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",389
	MVI Q7,R0
	ADDI #51,R0
	MVO R0,Q7+1
	;[390] 		percentage(2) = percentage(1) + 122
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",390
	MVI Q7+1,R0
	ADDI #122,R0
	MVO R0,Q7+2
	;[391] 		percentage(3) = percentage(2) + 25
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",391
	MVI Q7+2,R0
	ADDI #25,R0
	MVO R0,Q7+3
	;[392] 	elseif(level = 2) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",392
	B T128
T127:
	MVI V18,R0
	CMPI #2,R0
	BNE T129
	;[393] 		dificulty=1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",393
	MVII #1,R0
	MVO R0,V11
	;[394] 		#maximunScore = 110
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",394
	MVII #110,R0
	MVO R0,V12
	;[395] 		percentage(0) = 64
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",395
	MVII #64,R0
	MVO R0,Q7
	;[396] 		percentage(1) = percentage(0) + 64
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",396
	MVI Q7,R0
	ADDI #64,R0
	MVO R0,Q7+1
	;[397] 		percentage(2) = percentage(1) + 97
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",397
	MVI Q7+1,R0
	ADDI #97,R0
	MVO R0,Q7+2
	;[398] 		percentage(3) = percentage(2) + 25
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",398
	MVI Q7+2,R0
	ADDI #25,R0
	MVO R0,Q7+3
	;[399] 	elseif(level = 3) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",399
	B T128
T129:
	MVI V18,R0
	CMPI #3,R0
	BNE T130
	;[400] 		dificulty=2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",400
	MVII #2,R0
	MVO R0,V11
	;[401] 		#maximunScore = 130
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",401
	MVII #130,R0
	MVO R0,V12
	;[402] 		percentage(0) = 97
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",402
	MVII #97,R0
	MVO R0,Q7
	;[403] 		percentage(1) = percentage(0) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",403
	MVI Q7,R0
	ADDI #58,R0
	MVO R0,Q7+1
	;[404] 		percentage(2) = percentage(1) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",404
	MVI Q7+1,R0
	ADDI #58,R0
	MVO R0,Q7+2
	;[405] 		percentage(3) = percentage(2) + 25
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",405
	MVI Q7+2,R0
	ADDI #25,R0
	MVO R0,Q7+3
	;[406] 	elseif(level = 4) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",406
	B T128
T130:
	MVI V18,R0
	CMPI #4,R0
	BNE T131
	;[407] 		dificulty=2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",407
	MVII #2,R0
	MVO R0,V11
	;[408] 		#maximunScore = 150
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",408
	MVII #150,R0
	MVO R0,V12
	;[409] 		percentage(0) = 120
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",409
	MVII #120,R0
	MVO R0,Q7
	;[410] 		percentage(1) = percentage(0) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",410
	MVI Q7,R0
	ADDI #58,R0
	MVO R0,Q7+1
	;[411] 		percentage(2) = percentage(1) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",411
	MVI Q7+1,R0
	ADDI #58,R0
	MVO R0,Q7+2
	;[412] 		percentage(3) = percentage(2) + 17
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",412
	MVI Q7+2,R0
	ADDI #17,R0
	MVO R0,Q7+3
	;[413] 	elseif(level = 5) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",413
	B T128
T131:
	MVI V18,R0
	CMPI #5,R0
	BNE T132
	;[414] 		dificulty=3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",414
	MVII #3,R0
	MVO R0,V11
	;[415] 		#maximunScore = 250
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",415
	MVII #250,R0
	MVO R0,V12
	;[416] 		percentage(0) = 120
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",416
	MVII #120,R0
	MVO R0,Q7
	;[417] 		percentage(1) = percentage(0) + 66
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",417
	MVI Q7,R0
	ADDI #66,R0
	MVO R0,Q7+1
	;[418] 		percentage(2) = percentage(1) + 51
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",418
	MVI Q7+1,R0
	ADDI #51,R0
	MVO R0,Q7+2
	;[419] 		percentage(3) = percentage(2) + 17
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",419
	MVI Q7+2,R0
	ADDI #17,R0
	MVO R0,Q7+3
	;[420] 	elseif(level = 6) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",420
	B T128
T132:
	MVI V18,R0
	CMPI #6,R0
	BNE T133
	;[421] 		dificulty=3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",421
	MVII #3,R0
	MVO R0,V11
	;[422] 		#maximunScore = 500
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",422
	MVII #500,R0
	MVO R0,V12
	;[423] 		percentage(0) = 128
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",423
	MVII #128,R0
	MVO R0,Q7
	;[424] 		percentage(1) = percentage(0) + 76
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",424
	MVI Q7,R0
	ADDI #76,R0
	MVO R0,Q7+1
	;[425] 		percentage(2) = percentage(1) + 51
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",425
	MVI Q7+1,R0
	ADDI #51,R0
	MVO R0,Q7+2
	;[426] 		percentage(3) = percentage(2) + 17
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",426
	MVI Q7+2,R0
	ADDI #17,R0
	MVO R0,Q7+3
	;[427] 	elseif(level = 7) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",427
	B T128
T133:
	MVI V18,R0
	CMPI #7,R0
	BNE T134
	;[428] 		dificulty=4
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",428
	MVII #4,R0
	MVO R0,V11
	;[429] 		#maximunScore = 650
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",429
	MVII #650,R0
	MVO R0,V12
	;[430] 		percentage(0) = 117
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",430
	MVII #117,R0
	MVO R0,Q7
	;[431] 		percentage(1) = percentage(0) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",431
	MVI Q7,R0
	ADDI #58,R0
	MVO R0,Q7+1
	;[432] 		percentage(2) = percentage(1) + 58
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",432
	MVI Q7+1,R0
	ADDI #58,R0
	MVO R0,Q7+2
	;[433] 		percentage(3) = percentage(2) + 12
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",433
	MVI Q7+2,R0
	ADDI #12,R0
	MVO R0,Q7+3
	;[434] 	elseif(level = 8) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",434
	B T128
T134:
	MVI V18,R0
	CMPI #8,R0
	BNE T135
	;[435] 		dificulty=5
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",435
	MVII #5,R0
	MVO R0,V11
	;[436] 		#maximunScore = 750
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",436
	MVII #750,R0
	MVO R0,V12
	;[437] 		percentage(0) = 79
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",437
	MVII #79,R0
	MVO R0,Q7
	;[438] 		percentage(1) = percentage(0) + 79
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",438
	MVI Q7,R0
	ADDI #79,R0
	MVO R0,Q7+1
	;[439] 		percentage(2) = percentage(1) + 79
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",439
	MVI Q7+1,R0
	ADDI #79,R0
	MVO R0,Q7+2
	;[440] 		percentage(3) = percentage(2) + 8
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",440
	MVI Q7+2,R0
	ADDI #8,R0
	MVO R0,Q7+3
	;[441] 	elseif(level = 9) then 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",441
	B T128
T135:
	MVI V18,R0
	CMPI #9,R0
	BNE T136
	;[442] 		dificulty=6
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",442
	MVII #6,R0
	MVO R0,V11
	;[443] 		#maximunScore = 1000
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",443
	MVII #1000,R0
	MVO R0,V12
	;[444] 		percentage(0) = 81
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",444
	MVII #81,R0
	MVO R0,Q7
	;[445] 		percentage(1) = percentage(0) + 84
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",445
	MVI Q7,R0
	ADDI #84,R0
	MVO R0,Q7+1
	;[446] 		percentage(2) = percentage(1) + 50
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",446
	MVI Q7+1,R0
	ADDI #50,R0
	MVO R0,Q7+2
	;[447] 		percentage(3) = percentage(2) + 4
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",447
	MVI Q7+2,R0
	ADDI #4,R0
	MVO R0,Q7+3
	;[448] 	else
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",448
	B T128
T136:
	;[449] 		level = 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",449
	MVII #1,R0
	MVO R0,V18
	;[450] 		lives = 10
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",450
	MVII #10,R0
	MVO R0,V17
	;[451] 		gosub determinelevel
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",451
	CALL Q27
	;[452] 	end if
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",452
T128:
	;[453] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",453
	RETURN
	ENDP
	;[454] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",454
	;[455] clearAll:procedure 'clear everything on the screen
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",455
	; CLEARALL
Q31:	PROC
	BEGIN
	;[456] 	cls
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",456
	CALL CLRSCR
	;[457] 	ResetSprite(0)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",457
	CLRR R0
	MVO R0,_mobs
	MVO R0,_mobs+8
	NOP
	MVO R0,_mobs+16
	;[458] 	ResetSprite(1)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",458
	MVO R0,_mobs+1
	NOP
	MVO R0,_mobs+9
	MVO R0,_mobs+17
	;[459] 	ResetSprite(2)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",459
	NOP
	MVO R0,_mobs+2
	MVO R0,_mobs+10
	NOP
	MVO R0,_mobs+18
	;[460] 	ResetSprite(3)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",460
	MVO R0,_mobs+3
	NOP
	MVO R0,_mobs+11
	MVO R0,_mobs+19
	;[461] 	ResetSprite(4)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",461
	NOP
	MVO R0,_mobs+4
	MVO R0,_mobs+12
	NOP
	MVO R0,_mobs+20
	;[462] 	ResetSprite(5)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",462
	MVO R0,_mobs+5
	NOP
	MVO R0,_mobs+13
	MVO R0,_mobs+21
	;[463] 	ResetSprite(6)
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",463
	NOP
	MVO R0,_mobs+6
	MVO R0,_mobs+14
	NOP
	MVO R0,_mobs+22
	;[464] 	ResetSprite(7) 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",464
	MVO R0,_mobs+7
	NOP
	MVO R0,_mobs+15
	MVO R0,_mobs+23
	;[465] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",465
	RETURN
	ENDP
	;[466] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",466
	;[467] clearPower:procedure 'reset powers and object shown
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",467
	; CLEARPOWER
Q32:	PROC
	BEGIN
	;[468] 	invisible = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",468
	CLRR R0
	MVO R0,V7
	;[469] 	jump = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",469
	MVO R0,V14
	;[470] 	bonus_exp = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",470
	NOP
	MVO R0,V8
	;[471] 	bonus_lives = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",471
	MVO R0,V9
	;[472] 	object(0) = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",472
	NOP
	MVO R0,Q5
	;[473] 	object(1) = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",473
	MVO R0,Q5+1
	;[474] 	object(2) = 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",474
	NOP
	MVO R0,Q5+2
	;[475] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",475
	RETURN
	ENDP
	;[476] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",476
	;[477] add_points:	PROCEDURE 'score gained sound effect
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",477
	; ADD_POINTS
Q44:	PROC
	BEGIN
	;[478] 	#score = #score + 5
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",478
	MVI V15,R0
	ADDI #5,R0
	MVO R0,V15
	;[479] 	SOUND 1,400,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",479
	MVII #400,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[480] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",480
	CALL _wait
	;[481] 	SOUND 1,300,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",481
	MVII #300,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[482] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",482
	CALL _wait
	;[483] 	SOUND 1,500,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",483
	MVII #500,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[484] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",484
	CALL _wait
	;[485] 	SOUND 1,,0 ' Turn volume to zero
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",485
	CLRR R0
	MVO R0,508
	;[486] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",486
	RETURN
	ENDP
	;[487] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",487
	;[488] lose_points:	PROCEDURE 'score loss sound effect
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",488
	; LOSE_POINTS
Q45:	PROC
	BEGIN
	;[489] 	#score = #score - 15
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",489
	MVI V15,R0
	SUBI #15,R0
	MVO R0,V15
	;[490] 	SOUND 1,100,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",490
	MVII #100,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[491] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",491
	CALL _wait
	;[492] 	SOUND 1,500,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",492
	MVII #500,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[493] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",493
	CALL _wait
	;[494] 	SOUND 1,300,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",494
	MVII #300,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[495] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",495
	CALL _wait
	;[496] 	SOUND 1,,0 ' Turn volume to zero
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",496
	CLRR R0
	MVO R0,508
	;[497] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",497
	RETURN
	ENDP
	;[498] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",498
	;[499] add_lives:	PROCEDURE 'life gained sound effect
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",499
	; ADD_LIVES
Q43:	PROC
	BEGIN
	;[500] 	lives = lives + 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",500
	MVI V17,R0
	INCR R0
	MVO R0,V17
	;[501] 	SOUND 1,200,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",501
	MVII #200,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[502] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",502
	CALL _wait
	;[503] 	SOUND 1,300,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",503
	MVII #300,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[504] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",504
	CALL _wait
	;[505] 	SOUND 1,400,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",505
	MVII #400,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[506] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",506
	CALL _wait
	;[507] 	SOUND 1,500,14
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",507
	MVII #500,R0
	MVO R0,497
	SWAP R0
	MVO R0,501
	MVII #14,R0
	MVO R0,508
	;[508] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",508
	CALL _wait
	;[509] 	SOUND 1,,0 ' Turn volume to zero
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",509
	CLRR R0
	MVO R0,508
	;[510] end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",510
	RETURN
	ENDP
	;[511] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",511
	;[512] end:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",512
	; END
Q34:	;[513] 	wait
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",513
	CALL _wait
	;[514] 	print at SCREENPOS(6, 5) color CS_RED, "Good Bye!"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",514
	MVII #618,R0
	MVO R0,_screen
	MVII #2,R0
	MVO R0,_color
	MVI _screen,R4
	MVII #312,R0
	XOR _color,R0
	MVO@ R0,R4
	XORI #832,R0
	MVO@ R0,R4
	MVO@ R0,R4
	XORI #88,R0
	MVO@ R0,R4
	XORI #544,R0
	MVO@ R0,R4
	XORI #272,R0
	MVO@ R0,R4
	XORI #984,R0
	MVO@ R0,R4
	XORI #224,R0
	MVO@ R0,R4
	XORI #544,R0
	MVO@ R0,R4
	MVO R4,_screen
	;[515] 	goto end
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",515
	B Q34
	;[516] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",516
	;[517] 	'graphics
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",517
	;[518] player:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",518
	; PLAYER
Q12:	;[519] 	'frame 0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",519
	;[520] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",520
	;[521] 	BITMAP "#.####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",521
	DECLE 48188
	;[522] 	BITMAP "#.######"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",522
	;[523] 	BITMAP "######.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",523
	DECLE 64959
	;[524] 	BITMAP "..####.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",524
	;[525] 	BITMAP "..####.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",525
	DECLE 15677
	;[526] 	BITMAP "..#....."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",526
	;[527] 	BITMAP "..#....."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",527
	DECLE 8224
	;[528] 	'frame 1
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",528
	;[529] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",529
	;[530] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",530
	DECLE 15420
	;[531] 	BITMAP "#.####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",531
	;[532] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",532
	DECLE 65468
	;[533] 	BITMAP "..####.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",533
	;[534] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",534
	DECLE 15421
	;[535] 	BITMAP "..#..#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",535
	;[536] 	BITMAP "..#....."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",536
	DECLE 8228
	;[537] 	'frame 2
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",537
	;[538] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",538
	;[539] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",539
	DECLE 15420
	;[540] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",540
	;[541] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",541
	DECLE 65340
	;[542] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",542
	;[543] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",543
	DECLE 15420
	;[544] 	BITMAP "..#..#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",544
	;[545] 	BITMAP "..#..#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",545
	DECLE 9252
	;[546] 	'frame 3
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",546
	;[547] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",547
	;[548] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",548
	DECLE 15420
	;[549] 	BITMAP "..####.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",549
	;[550] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",550
	DECLE 65341
	;[551] 	BITMAP "#.####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",551
	;[552] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",552
	DECLE 15548
	;[553] 	BITMAP "..#..#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",553
	;[554] 	BITMAP ".....#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",554
	DECLE 1060
	;[555] 	'frame 4
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",555
	;[556] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",556
	;[557] 	BITMAP "..####.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",557
	DECLE 15676
	;[558] 	BITMAP "######.#"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",558
	;[559] 	BITMAP "#.######"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",559
	DECLE 49149
	;[560] 	BITMAP "#.####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",560
	;[561] 	BITMAP "#.####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",561
	DECLE 48316
	;[562] 	BITMAP ".....#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",562
	;[563] 	BITMAP ".....#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",563
	DECLE 1028
	;[564] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",564
	;[565] tiles:	'heart icon
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",565
	; TILES
Q13:	;[566] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",566
	;[567] 	BITMAP ".##.##.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",567
	DECLE 27648
	;[568] 	BITMAP "#.##.##."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",568
	;[569] 	BITMAP "#######."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",569
	DECLE 65206
	;[570] 	BITMAP ".#####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",570
	;[571] 	BITMAP "..###..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",571
	DECLE 14460
	;[572] 	BITMAP "...#...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",572
	;[573] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",573
	DECLE 16
	;[574] 	'empty heart icon
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",574
	;[575] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",575
	;[576] 	BITMAP ".##.##.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",576
	DECLE 27648
	;[577] 	BITMAP "##.##.#."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",577
	;[578] 	BITMAP "#.....#."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",578
	DECLE 33498
	;[579] 	BITMAP ".#...#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",579
	;[580] 	BITMAP "..#.#..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",580
	DECLE 10308
	;[581] 	BITMAP "...#...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",581
	;[582] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",582
	DECLE 16
	;[583] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",583
	;[584] street:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",584
	; STREET
Q14:	;[585] 	'left
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",585
	;[586] 	BITMAP "....##.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",586
	;[587] 	BITMAP "....##.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",587
	DECLE 3084
	;[588] 	BITMAP "....##.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",588
	;[589] 	BITMAP "...###.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",589
	DECLE 7180
	;[590] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",590
	;[591] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",591
	DECLE 6168
	;[592] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",592
	;[593] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",593
	DECLE 6168
	;[594] 	'center
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",594
	;[595] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",595
	;[596] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",596
	DECLE 49344
	;[597] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",597
	;[598] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",598
	DECLE 49344
	;[599] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",599
	;[600] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",600
	DECLE 49344
	;[601] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",601
	;[602] 	BITMAP "##......"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",602
	DECLE 49344
	;[603] 	'left
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",603
	;[604] 	BITMAP "..##...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",604
	;[605] 	BITMAP "..##...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",605
	DECLE 12336
	;[606] 	BITMAP "..##...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",606
	;[607] 	BITMAP "..##...."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",607
	DECLE 12336
	;[608] 	BITMAP "..###..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",608
	;[609] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",609
	DECLE 6200
	;[610] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",610
	;[611] 	BITMAP "...##..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",611
	DECLE 6168
	;[612] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",612
	;[613] apple:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",613
	; APPLE
Q18:	;[614] 	BITMAP ".....#.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",614
	;[615] 	BITMAP "....#..."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",615
	DECLE 2052
	;[616] 	BITMAP "..##.##."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",616
	;[617] 	BITMAP ".#######"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",617
	DECLE 32566
	;[618] 	BITMAP ".#######"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",618
	;[619] 	BITMAP ".#######"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",619
	DECLE 32639
	;[620] 	BITMAP "..#####."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",620
	;[621] 	BITMAP "..##.##."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",621
	DECLE 13886
	;[622] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",622
	;[623] nothing:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",623
	; NOTHING
Q15:	;[624] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",624
	;[625] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",625
	DECLE 0
	;[626] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",626
	;[627] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",627
	DECLE 0
	;[628] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",628
	;[629] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",629
	DECLE 0
	;[630] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",630
	;[631] 	BITMAP "........"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",631
	DECLE 0
	;[632] 	
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",632
	;[633] rock:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",633
	; ROCK
Q16:	;[634] 	BITMAP "..#####."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",634
	;[635] 	BITMAP ".#.#####"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",635
	DECLE 24382
	;[636] 	BITMAP "####..##"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",636
	;[637] 	BITMAP "####.###"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",637
	DECLE 63475
	;[638] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",638
	;[639] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",639
	DECLE 65535
	;[640] 	BITMAP ".###.##."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",640
	;[641] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",641
	DECLE 15478
	;[642] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",642
	;[643] coin:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",643
	; COIN
Q17:	;[644] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",644
	;[645] 	BITMAP ".######."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",645
	DECLE 32316
	;[646] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",646
	;[647] 	BITMAP "###..###"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",647
	DECLE 59391
	;[648] 	BITMAP "###..###"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",648
	;[649] 	BITMAP "########"
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",649
	DECLE 65511
	;[650] 	BITMAP ".######."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",650
	;[651] 	BITMAP "..####.."
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",651
	DECLE 15486
	;[652] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",652
	;[653] 	' 49 bitmaps
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",653
	;[654] screen_bitmaps_0:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",654
	; SCREEN_BITMAPS_0
Q8:	;[655] 	DATA $FFFF,$E0FF,$E0E0,$E0E0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",655
	DECLE 65535
	DECLE 57599
	DECLE 57568
	DECLE 57568
	;[656] 	DATA $FFFF,$00FF,$0000,$0000
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",656
	DECLE 65535
	DECLE 255
	DECLE 0
	DECLE 0
	;[657] 	DATA $FFFF,$07FF,$0707,$0707
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",657
	DECLE 65535
	DECLE 2047
	DECLE 1799
	DECLE 1799
	;[658] 	DATA $0100,$0D07,$1F1F,$FF7F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",658
	DECLE 256
	DECLE 3335
	DECLE 7967
	DECLE 65407
	;[659] 	DATA $76E0,$BA6F,$F7CD,$FFFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",659
	DECLE 30432
	DECLE 47727
	DECLE 63437
	DECLE 65535
	;[660] 	DATA $E0E0,$E0E0,$E0E0,$E0E0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",660
	DECLE 57568
	DECLE 57568
	DECLE 57568
	DECLE 57568
	;[661] 	DATA $6000,$C390,$1424,$6394
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",661
	DECLE 24576
	DECLE 50064
	DECLE 5156
	DECLE 25492
	;[662] 	DATA $0000,$3B00,$45C5,$3BC5
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",662
	DECLE 0
	DECLE 15104
	DECLE 17861
	DECLE 15301
	;[663] 	DATA $0000,$D900,$3C24,$9D20
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",663
	DECLE 0
	DECLE 55552
	DECLE 15396
	DECLE 40224
	;[664] 	DATA $0707,$0707,$0707,$0707
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",664
	DECLE 1799
	DECLE 1799
	DECLE 1799
	DECLE 1799
	;[665] 	DATA $E000,$4542,$4242,$FF4A
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",665
	DECLE 57344
	DECLE 17730
	DECLE 16962
	DECLE 65354
	;[666] 	DATA $0000,$A600,$AFA9,$47C8
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",666
	DECLE 0
	DECLE 42496
	DECLE 44969
	DECLE 18376
	;[667] 	DATA $0000,$3C00,$3040,$7408
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",667
	DECLE 0
	DECLE 15360
	DECLE 12352
	DECLE 29704
	;[668] 	DATA $FFFF,$FEFE,$FCFC,$F8F8
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",668
	DECLE 65535
	DECLE 65278
	DECLE 64764
	DECLE 63736
	;[669] 	DATA $0F00,$1F1F,$3F3F,$7F7F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",669
	DECLE 3840
	DECLE 7967
	DECLE 16191
	DECLE 32639
	;[670] 	DATA $FF00,$FFFF,$FFFF,$FFFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",670
	DECLE 65280
	DECLE 65535
	DECLE 65535
	DECLE 65535
	;[671] screen_bitmaps_1:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",671
	; SCREEN_BITMAPS_1
Q9:	;[672] 	DATA $FE00,$FEFE,$FEFE,$FEFE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",672
	DECLE 65024
	DECLE 65278
	DECLE 65278
	DECLE 65278
	;[673] 	DATA $7F00,$7F7F,$7F7F,$BF7F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",673
	DECLE 32512
	DECLE 32639
	DECLE 32639
	DECLE 49023
	;[674] 	DATA $F000,$F8F8,$FCFC,$FEFE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",674
	DECLE 61440
	DECLE 63736
	DECLE 64764
	DECLE 65278
	;[675] 	DATA $0101,$0000,$0000,$0000
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",675
	DECLE 257
	DECLE 0
	DECLE 0
	DECLE 0
	;[676] 	DATA $FFFF,$7FFF,$3F7F,$1F1F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",676
	DECLE 65535
	DECLE 32767
	DECLE 16255
	DECLE 7967
	;[677] 	DATA $F0F0,$C0E0,$80C0,$0080
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",677
	DECLE 61680
	DECLE 49376
	DECLE 32960
	DECLE 128
	;[678] 	DATA $0000,$0101,$0303,$0707
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",678
	DECLE 0
	DECLE 257
	DECLE 771
	DECLE 1799
	;[679] 	DATA $FDFD,$FDFD,$FDFD,$FBFD
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",679
	DECLE 65021
	DECLE 65021
	DECLE 65021
	DECLE 64509
	;[680] 	DATA $BFBF,$BFBF,$BFBF,$DFDF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",680
	DECLE 49087
	DECLE 49087
	DECLE 49087
	DECLE 57311
	;[681] 	DATA $0000,$8080,$C0C0,$E0E0
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",681
	DECLE 0
	DECLE 32896
	DECLE 49344
	DECLE 57568
	;[682] 	DATA $070F,$0307,$0101,$0000
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",682
	DECLE 1807
	DECLE 775
	DECLE 257
	DECLE 0
	;[683] 	DATA $FFFF,$FFFF,$FFFF,$7FFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",683
	DECLE 65535
	DECLE 65535
	DECLE 65535
	DECLE 32767
	;[684] 	DATA $FEFF,$FCFE,$F8FC,$F0F8
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",684
	DECLE 65279
	DECLE 64766
	DECLE 63740
	DECLE 61688
	;[685] 	DATA $0F0F,$1F1F,$3F3F,$7F7F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",685
	DECLE 3855
	DECLE 7967
	DECLE 16191
	DECLE 32639
	;[686] 	DATA $FBFB,$FBFB,$FBFB,$F7F7
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",686
	DECLE 64507
	DECLE 64507
	DECLE 64507
	DECLE 63479
	;[687] 	DATA $DFDF,$DFDF,$EFDF,$EFEF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",687
	DECLE 57311
	DECLE 57311
	DECLE 61407
	DECLE 61423
	;[688] screen_bitmaps_2:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",688
	; SCREEN_BITMAPS_2
Q10:	;[689] 	DATA $F0F0,$F8F8,$FCFC,$FEFE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",689
	DECLE 61680
	DECLE 63736
	DECLE 64764
	DECLE 65278
	;[690] 	DATA $3F7F,$1F1F,$070F,$0307
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",690
	DECLE 16255
	DECLE 7967
	DECLE 1807
	DECLE 775
	;[691] 	DATA $E000,$4340,$4744,$FB4C
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",691
	DECLE 57344
	DECLE 17216
	DECLE 18244
	DECLE 64332
	;[692] 	DATA $0000,$3400,$9595,$8819
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",692
	DECLE 0
	DECLE 13312
	DECLE 38293
	DECLE 34841
	;[693] 	DATA $0C00,$C604,$E424,$EE04
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",693
	DECLE 3072
	DECLE 50692
	DECLE 58404
	DECLE 60932
	;[694] 	DATA $E0E0,$C0C0,$8080,$0000
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",694
	DECLE 57568
	DECLE 49344
	DECLE 32896
	DECLE 0
	;[695] 	DATA $F7F7,$F7F7,$EFF7,$EFEF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",695
	DECLE 63479
	DECLE 63479
	DECLE 61431
	DECLE 61423
	;[696] 	DATA $EFEF,$EFEF,$F7F7,$F7F7
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",696
	DECLE 61423
	DECLE 61423
	DECLE 63479
	DECLE 63479
	;[697] 	DATA $EFEF,$EFEF,$DFDF,$DFDF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",697
	DECLE 61423
	DECLE 61423
	DECLE 57311
	DECLE 57311
	;[698] 	DATA $F7F7,$FBF7,$FBFB,$FBFB
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",698
	DECLE 63479
	DECLE 64503
	DECLE 64507
	DECLE 64507
	;[699] 	DATA $DFDF,$BFDF,$BFBF,$BFBF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",699
	DECLE 57311
	DECLE 49119
	DECLE 49087
	DECLE 49087
	;[700] 	DATA $FBFB,$FDFD,$FDFD,$FDFD
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",700
	DECLE 64507
	DECLE 65021
	DECLE 65021
	DECLE 65021
	;[701] 	DATA $BFBF,$7F7F,$7F7F,$7F7F
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",701
	DECLE 49087
	DECLE 32639
	DECLE 32639
	DECLE 32639
	;[702] 	DATA $FEFD,$FEFE,$FEFE,$FEFE
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",702
	DECLE 65277
	DECLE 65278
	DECLE 65278
	DECLE 65278
	;[703] 	DATA $E0E0,$E0E0,$FFE0,$FFFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",703
	DECLE 57568
	DECLE 57568
	DECLE 65504
	DECLE 65535
	;[704] 	DATA $0000,$0000,$FF00,$FFFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",704
	DECLE 0
	DECLE 0
	DECLE 65280
	DECLE 65535
	;[705] screen_bitmaps_3:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",705
	; SCREEN_BITMAPS_3
Q11:	;[706] 	DATA $0707,$0707,$FF07,$FFFF
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",706
	DECLE 1799
	DECLE 1799
	DECLE 65287
	DECLE 65535
	;[707] 
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",707
	;[708] 	REM 20x12 cards
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",708
	;[709] screen_cards:
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",709
	; SCREEN_CARDS
Q26:	;[710] 	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E00,$1E08,$1E08,$1E08,$1E10
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",710
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 7680
	DECLE 7688
	DECLE 7688
	DECLE 7688
	DECLE 7696
	;[711] 	DATA $1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1E28,$1E37,$1E3F,$1E47,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",711
	DECLE 4608
	DECLE 6687
	DECLE 6695
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 6687
	DECLE 6695
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 7720
	DECLE 7735
	DECLE 7743
	DECLE 7751
	DECLE 7752
	;[712] 	DATA $1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",712
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 6687
	DECLE 6695
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[713] 	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",713
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 6687
	DECLE 6695
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[714] 	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1E57,$1E5F,$1E67,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",714
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 4608
	DECLE 7720
	DECLE 7767
	DECLE 7775
	DECLE 7783
	DECLE 7752
	;[715] 	DATA $2400,$186E,$1000,$1874,$187C,$1884,$187C,$187C,$188C,$187C,$1894,$189E,$18A6,$2400,$2400,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",715
	DECLE 9216
	DECLE 6254
	DECLE 4096
	DECLE 6260
	DECLE 6268
	DECLE 6276
	DECLE 6268
	DECLE 6268
	DECLE 6284
	DECLE 6268
	DECLE 6292
	DECLE 6302
	DECLE 6310
	DECLE 9216
	DECLE 9216
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[716] 	DATA $2400,$18AE,$18B4,$2000,$2000,$18BC,$2000,$2000,$18C4,$2000,$2000,$18CC,$18D6,$18DE,$2400,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",716
	DECLE 9216
	DECLE 6318
	DECLE 6324
	DECLE 8192
	DECLE 8192
	DECLE 6332
	DECLE 8192
	DECLE 8192
	DECLE 6340
	DECLE 8192
	DECLE 8192
	DECLE 6348
	DECLE 6358
	DECLE 6366
	DECLE 9216
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[717] 	DATA $18E6,$1000,$18EC,$2000,$2000,$18F4,$2000,$2000,$18FC,$2000,$2000,$1904,$1000,$190E,$2400,$1E28,$1F17,$1F1F,$1F27,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",717
	DECLE 6374
	DECLE 4096
	DECLE 6380
	DECLE 8192
	DECLE 8192
	DECLE 6388
	DECLE 8192
	DECLE 8192
	DECLE 6396
	DECLE 8192
	DECLE 8192
	DECLE 6404
	DECLE 4096
	DECLE 6414
	DECLE 9216
	DECLE 7720
	DECLE 7959
	DECLE 7967
	DECLE 7975
	DECLE 7752
	;[718] 	DATA $192E,$18B4,$2000,$2000,$2000,$1934,$2000,$2000,$193C,$2000,$2000,$2000,$18CC,$189E,$18A6,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",718
	DECLE 6446
	DECLE 6324
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6452
	DECLE 8192
	DECLE 8192
	DECLE 6460
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6348
	DECLE 6302
	DECLE 6310
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[719] 	DATA $1000,$18EC,$2000,$2000,$2000,$1944,$2000,$2000,$194C,$2000,$2000,$2000,$1904,$1000,$18D6,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",719
	DECLE 4096
	DECLE 6380
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6468
	DECLE 8192
	DECLE 8192
	DECLE 6476
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6404
	DECLE 4096
	DECLE 6358
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[720] 	DATA $18B4,$2000,$2000,$2000,$2000,$1954,$2000,$2000,$195C,$2000,$2000,$2000,$2000,$18CC,$1000,$1E28,$1600,$1600,$1600,$1E48
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",720
	DECLE 6324
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6484
	DECLE 8192
	DECLE 8192
	DECLE 6492
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6348
	DECLE 4096
	DECLE 7720
	DECLE 5632
	DECLE 5632
	DECLE 5632
	DECLE 7752
	;[721] 	DATA $18EC,$2000,$2000,$2000,$2000,$1964,$2000,$2000,$196C,$2000,$2000,$2000,$2000,$1904,$1000,$1F70,$1F78,$1F78,$1F78,$1F80
	SRCFILE "C:\Users\Josue\OneDrive\Documents\UMass Dartmouth\Classes\Fall 2017\CIS 272\Honor Project\RUNNERZ\runnerZ.BAS",721
	DECLE 6380
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6500
	DECLE 8192
	DECLE 8192
	DECLE 6508
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 8192
	DECLE 6404
	DECLE 4096
	DECLE 8048
	DECLE 8056
	DECLE 8056
	DECLE 8056
	DECLE 8064
	;ENDFILE
	SRCFILE "",0
intybasic_fastmult:	equ 1	; Forces to include fast multiplication
        ;
        ; Epilogue for IntyBASIC programs
        ; by Oscar Toledo G.  http://nanochess.org/
        ;
        ; Revision: Jan/30/2014. Moved GRAM code below MOB updates.
        ;                        Added comments.
        ; Revision: Feb/26/2014. Optimized access to collision registers
        ;                        per DZ-Jay suggestion. Added scrolling
        ;                        routines with optimization per intvnut
        ;                        suggestion. Added border/mask support.
        ; Revision: Apr/02/2014. Added support to set MODE (color stack
        ;                        or foreground/background), added support
        ;                        for SCREEN statement.
        ; Revision: Aug/19/2014. Solved bug in bottom scroll, moved an
        ;                        extra unneeded line.
        ; Revision: Aug/26/2014. Integrated music player and NTSC/PAL
        ;                        detection.
        ; Revision: Oct/24/2014. Adjust in some comments.
        ; Revision: Nov/13/2014. Integrated Joseph Zbiciak's routines
        ;                        for printing numbers.
        ; Revision: Nov/17/2014. Redesigned MODE support to use a single
        ;                        variable.
        ; Revision: Nov/21/2014. Added Intellivoice support routines made
        ;                        by Joseph Zbiciak.
	; Revision: Dec/11/2014. Optimized keypad decode routines.
	; Revision: Jan/25/2015. Added marker for insertion of ON FRAME GOSUB
	; Revision: Feb/17/2015. Allows to deactivate music player (PLAY NONE)
	; Revision: Apr/21/2015. Accelerates common case of keypad not pressed.
	;                        Added ECS ROM disable code.
	; Revision: Apr/22/2015. Added Joseph Zbiciak accelerated multiplication
	;                        routines.
	; Revision: Jun/04/2015. Optimized play_music (per GroovyBee suggestion)
	; Revision: Jul/25/2015. Added infinite loop at start to avoid crashing
	;                        with empty programs. Solved bug where _color
	;                        didn't started with white.
	; Revision: Aug/20/2015. Moved ECS mapper disable code so nothing gets
	;                        after it (GroovyBee 42K sample code)
	; Revision: Aug/21/2015. Added Joseph Zbiciak routines for JLP Flash
	;                        handling.
	; Revision: Aug/31/2015. Added CPYBLK2 for SCREEN fifth argument.
	; Revision: Sep/01/2015. Defined labels Q1 and Q2 as alias.
	; Revision: Jan/22/2016. Music player allows not to use noise channel
	;                        for drums. Allows setting music volume.
	; Revision: Jan/23/2016. Added jump inside of music (for MUSIC JUMP)
	; Revision: May/03/2016. Preserves current mode in bit 0 of _mode_select

	;
	; Avoids empty programs to crash
	; 
stuck:	B stuck

	;
	; Copy screen helper for SCREEN wide statement
	;

CPYBLK2:	PROC
	MOVR R0,R3		; Offset
	MOVR R5,R2
	PULR R0
	PULR R1
	PULR R5
	PULR R4
	PSHR R2
	SUBR R1,R3

@@1:    PSHR R3
	MOVR R1,R3              ; Init line copy
@@2:    MVI@ R4,R2              ; Copy line
        MVO@ R2,R5
        DECR R3
        BNE @@2
        PULR R3                 ; Add offset to start in next line
        ADDR R3,R4
	SUBR R1,R5
        ADDI #20,R5
        DECR R0                 ; Count lines
        BNE @@1

	RETURN
	ENDP

        ;
        ; Copy screen helper for SCREEN statement
        ;
CPYBLK: PROC
        BEGIN
        MOVR R3,R4
        MOVR R2,R5

@@1:    MOVR R1,R3              ; Init line copy
@@2:    MVI@ R4,R2              ; Copy line
        MVO@ R2,R5
        DECR R3
        BNE @@2
        MVII #20,R3             ; Add offset to start in next line
        SUBR R1,R3
        ADDR R3,R4
        ADDR R3,R5
        DECR R0                 ; Count lines
        BNE @@1
	RETURN
        ENDP

        ;
        ; Wait for interruption
        ;
_wait:  PROC

    IF DEFINED intybasic_keypad
        MVI $01FF,R0
        COMR R0
        ANDI #$FF,R0
        CMP _cnt1_p0,R0
        BNE @@2
        CMP _cnt1_p1,R0
        BNE @@2
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@4
        MVII #_keypad_table,R4
    REPEAT 6
        CMP@ R4,R0
        BEQ @@4
	CMP@ R4,R0
        BEQ @@4
    ENDR
	INCR R4
@@4:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt1_key

@@2:    MVI _cnt1_p1,R1
        MVO R1,_cnt1_p0
        MVO R0,_cnt1_p1

        MVI $01FE,R0
        COMR R0
        ANDI #$FF,R0
        CMP _cnt2_p0,R0
        BNE @@5
        CMP _cnt2_p1,R0
        BNE @@5
	TSTR R0		; Accelerates common case of key not pressed
	MVII #_keypad_table+13,R4
	BEQ @@7
        MVII #_keypad_table,R4
    REPEAT 6
        CMP@ R4,R0
        BEQ @@7
	CMP@ R4,R0
	BEQ @@7
    ENDR

	INCR R4
@@7:    SUBI #_keypad_table+1,R4
	MVO R4,_cnt2_key

@@5:    MVI _cnt2_p1,R1
        MVO R1,_cnt2_p0
        MVO R0,_cnt2_p1
    ENDI

        CLRR    R0
        MVO     R0,_int         ; Clears waiting flag
@@1:    CMP     _int,  R0       ; Waits for change
        BEQ     @@1
        JR      R5              ; Returns
        ENDP

        ;
        ; Keypad table
        ;
_keypad_table:          PROC
        DECLE $48,$81,$41,$21,$82,$42,$22,$84,$44,$24,$88,$28
        ENDP

_pal1_vector:    PROC
        MVII #_pal2_vector,R0
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1
        MVII #3,R0
        MVO R0,_ntsc
        JR R5
        ENDP

_pal2_vector:    PROC
        MVII #_int_vector,R0     ; Point to "real" interruption handler
        MVO R0,ISRVEC
        SWAP R0
        MVO R0,ISRVEC+1
        MVII #4,R0
        MVO R0,_ntsc
	CLRR R0
	CLRR R4
	MVII #$18,R1
@@1:	MVO@ R0,R4
	DECR R1
	BNE @@1
        JR R5
        ENDP

        ;
        ; Interruption routine
        ;
_int_vector:     PROC
        BEGIN

        MVO     R0,     $20     ; Activates display

    IF DEFINED intybasic_stack
	CMPI #$308,R6
	BNC @@vs
	MVI $21,R0	; Activates Color Stack mode
	CLRR R0
	MVO R0,$28
	MVO R0,$29
	MVO R0,$2A
	MVO R0,$2B
	MVII #@@vs1,R4
	MVII #$200,R5
	MVII #20,R1
@@vs2:	MVI@ R4,R0
	MVO@ R0,R5
	DECR R1
	BNE @@vs2
	RETURN

	; Stack Overflow message
@@vs1:	DECLE 0,0,0,$33*8+7,$54*8+7,$41*8+7,$43*8+7,$4B*8+7,$00*8+7
	DECLE $4F*8+7,$56*8+7,$45*8+7,$52*8+7,$46*8+7,$4C*8+7
	DECLE $4F*8+7,$57*8+7,0,0,0

@@vs:
    ENDI
        MVII    #1,     R0
        MVO     R0,     _int    ; Indicates interrupt happened

        MVI _mode_select,R0
        SARC R0,2
        BNOV @@vi0
	CLRR R1
        BNC @@vi14
        MVO R0,$21  ; Activates Foreground/Background mode
        INCR R1
	B @@vi15

@@vi14: MVI $21,R0  ; Activates Color Stack mode
        MVI _color,R0
        MVO R0,$28
        SWAP R0
        MVO R0,$29
        SLR R0,2
        SLR R0,2
        MVO R0,$2A
        SWAP R0
        MVO R0,$2B
@@vi15: MVO R1,_mode_select
	MVII #7,R0
        MVO R0,_color           ; Default color for PRINT "string"
@@vi0:
        MVI _border_color,R0
        MVO     R0,     $2C     ; Border color
        MVI _border_mask,R0
        MVO     R0,     $32     ; Border mask
        ;
        ; Save collision registers for further use and clear them
        ;
        MVII #$18,R4
        MVII #_col0,R5
        MVI@ R4,R0
        MVO@ R0,R5  ; _col0
        MVI@ R4,R0
        MVO@ R0,R5  ; _col1
        MVI@ R4,R0
        MVO@ R0,R5  ; _col2
        MVI@ R4,R0
        MVO@ R0,R5  ; _col3
        MVI@ R4,R0
        MVO@ R0,R5  ; _col4
        MVI@ R4,R0
        MVO@ R0,R5  ; _col5
        MVI@ R4,R0
        MVO@ R0,R5  ; _col6
        MVI@ R4,R0
        MVO@ R0,R5  ; _col7
        MVII #$18,R5
        CLRR R0
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        MVO@ R0,R5
        
    IF DEFINED intybasic_scroll

        ;
        ; Scrolling things
        ;
        MVI _scroll_x,R0
        MVO R0,$30
        MVI _scroll_y,R0
        MVO R0,$31
    ENDI

        ;
        ; Updates sprites (MOBs)
        ;
        MVII #_mobs,R4
        MVII #$0,R5     ; X-coordinates
        MVII #8,R1
@@vi2:  MVI@ R4,R0
        MVO@ R0,R5
        MVI@ R4,R0
        MVO@ R0,R5
        MVI@ R4,R0
        MVO@ R0,R5
        DECR R1
        BNE @@vi2

    IF DEFINED intybasic_music
     	MVI _ntsc,R0
        TSTR R0         ; PAL?
        BEQ @@vo97      ; Yes, always emit sound
	MVI _music_frame,R0
	INCR R0
	CMPI #6,R0
	BNE @@vo14
	CLRR R0
@@vo14:	MVO R0,_music_frame
	BEQ @@vo15
@@vo97:	CALL _emit_sound
@@vo15:
    ENDI

        ;
        ; Detect GRAM definition
        ;
        MVI _gram_bitmap,R4
        TSTR R4
        BEQ @@vi1
        MVI _gram_target,R1
        SLL R1,2
        SLL R1,1
        ADDI #$3800,R1
        MOVR R1,R5
        MVI _gram_total,R0
@@vi3:
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        DECR R0
        BNE @@vi3
        MVO R0,_gram_bitmap
@@vi1:
        MVI _gram2_bitmap,R4
        TSTR R4
        BEQ @@vii1
        MVI _gram2_target,R1
        SLL R1,2
        SLL R1,1
        ADDI #$3800,R1
        MOVR R1,R5
        MVI _gram2_total,R0
@@vii3:
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        MVI@    R4,     R1
        MVO@    R1,     R5
        SWAP    R1
        MVO@    R1,     R5
        DECR R0
        BNE @@vii3
        MVO R0,_gram2_bitmap
@@vii1:

    IF DEFINED intybasic_scroll
        ;
        ; Frame scroll support
        ;
        MVI _scroll_d,R0
        TSTR R0
        BEQ @@vi4
        CLRR R1
        MVO R1,_scroll_d
        DECR R0     ; Left
        BEQ @@vi5
        DECR R0     ; Right
        BEQ @@vi6
        DECR R0     ; Top
        BEQ @@vi7
        DECR R0     ; Bottom
        BEQ @@vi8
        B @@vi4

@@vi5:  MVII #$0200,R4
        MOVR R4,R5
        INCR R5
        MVII #12,R1
@@vi12: MVI@ R4,R2
        MVI@ R4,R3
        REPEAT 8
        MVO@ R2,R5
        MVI@ R4,R2
        MVO@ R3,R5
        MVI@ R4,R3
        ENDR
        MVO@ R2,R5
        MVI@ R4,R2
        MVO@ R3,R5
        MVO@ R2,R5
        INCR R4
        INCR R5
        DECR R1
        BNE @@vi12
        B @@vi4

@@vi6:  MVII #$0201,R4
        MVII #$0200,R5
        MVII #12,R1
@@vi11:
        REPEAT 19
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        INCR R4
        INCR R5
        DECR R1
        BNE @@vi11
        B @@vi4
    
        ;
        ; Complex routine to be ahead of STIC display
        ; Moves first the top 6 lines, saves intermediate line
        ; Then moves the bottom 6 lines and restores intermediate line
        ;
@@vi7:  MVII #$0264,R4
        MVII #5,R1
        MVII #_scroll_buffer,R5
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        MOVR R4,R5
        ADDI #20,R5
@@vi10:
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        SUBI #40,R5
        DECR R1
        BNE @@vi10
        MVII #$02C8,R4
        MVII #$02DC,R5
        MVII #5,R1
@@vi13:
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        SUBI #40,R4
        SUBI #40,R5
        DECR R1
        BNE @@vi13
        MVII #_scroll_buffer,R4
        REPEAT 20
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        B @@vi4

@@vi8:  MVII #$0214,R4
        MVII #$0200,R5
        MVII #$DC/4,R1
@@vi9:  
        REPEAT 4
        MVI@ R4,R0
        MVO@ R0,R5
        ENDR
        DECR R1
        BNE @@vi9
        B @@vi4

@@vi4:
    ENDI

    IF DEFINED intybasic_voice
        ;
        ; Intellivoice support
        ;
        CALL IV_ISR
    ENDI

        ;
        ; Random number generator
        ;
	CALL _next_random

    IF DEFINED intybasic_music
	; Generate sound for next frame
       	MVI _ntsc,R0
        TSTR R0         ; PAL?
        BEQ @@vo98      ; Yes, always generate sound
	MVI _music_frame,R0
	TSTR R0
	BEQ @@vo16
@@vo98: CALL _generate_music
@@vo16:
    ENDI

        ; Increase frame number
        MVI _frame,R0
        INCR R0
        MVO R0,_frame

	; This mark is for ON FRAME GOSUB support

        RETURN
        ENDP

	;
	; Generates the next random number
	;
_next_random:	PROC

MACRO _ROR
	RRC R0,1
	MOVR R0,R2
	SLR R2,2
	SLR R2,2
	ANDI #$0800,R2
	SLR R2,2
	SLR R2,2
	ANDI #$007F,R0
	XORR R2,R0
ENDM
        MVI _rand,R0
        SETC
        _ROR
        XOR _frame,R0
        _ROR
        XOR _rand,R0
        _ROR
        XORI #9,R0
        MVO R0,_rand
	JR R5
	ENDP

    IF DEFINED intybasic_music

        ;
        ; Music player, comes from my game Princess Quest for Intellivision
        ; so it's a practical tracker used in a real game ;) and with enough
        ; features.
        ;

        ; NTSC frequency for notes (based on 3.579545 mhz)
ntsc_note_table:    PROC
        ; Silence - 0
        DECLE 0
        ; Octave 2 - 1
        DECLE 1721,1621,1532,1434,1364,1286,1216,1141,1076,1017,956,909
        ; Octave 3 - 13
        DECLE 854,805,761,717,678,639,605,571,538,508,480,453
        ; Octave 4 - 25
        DECLE 427,404,380,360,339,321,302,285,270,254,240,226
        ; Octave 5 - 37
        DECLE 214,202,191,180,170,160,151,143,135,127,120,113
        ; Octave 6 - 49
        DECLE 107,101,95,90,85,80,76,71,67,64,60,57
        ; Octave 7 - 61
        ; Space for two notes more
	ENDP

        ; PAL frequency for notes (based on 4 mhz)
pal_note_table:    PROC
        ; Silence - 0
        DECLE 0
        ; Octava 2 - 1
        DECLE 1923,1812,1712,1603,1524,1437,1359,1276,1202,1136,1068,1016
        ; Octava 3 - 13
        DECLE 954,899,850,801,758,714,676,638,601,568,536,506
        ; Octava 4 - 25
        DECLE 477,451,425,402,379,358,338,319,301,284,268,253
        ; Octava 5 - 37
        DECLE 239,226,213,201,190,179,169,159,150,142,134,127
        ; Octava 6 - 49
        DECLE 120,113,106,100,95,89,84,80,75,71,67,63
        ; Octava 7 - 61
        ; Space for two notes more
	ENDP
    ENDI

        ;
        ; Music tracker init
        ;
_init_music:	PROC
    IF DEFINED intybasic_music
        MVI _ntsc,R0
        CMPI #1,R0
        MVII #ntsc_note_table,R0
        BEQ @@0
        MVII #pal_note_table,R0
@@0:    MVO R0,_music_table
        MVII #$38,R0	; $B8 blocks controllers o.O!
	MVO R0,_music_mix
        CLRR R0
    ELSE
	JR R5
    ENDI
	ENDP

    IF DEFINED intybasic_music
        ;
        ; Start music
        ; R0 = Pointer to music
        ;
_play_music:	PROC
	MOVR R0,R2
        MVII #1,R0
	MOVR R0,R3
	TSTR R2
	BEQ @@1
	MVI@ R2,R3
	INCR R2
@@1:	MVO R2,_music_start
	MVO R2,_music_p
	MVO R3,_music_t
	MVO R0,_music_tc
        JR R5

	ENDP

        ;
        ; Generate music
        ;
_generate_music:	PROC
	BEGIN
	MVI _music_mix,R0
	ANDI #$C0,R0
	XORI #$38,R0
	MVO R0,_music_mix
	CLRR R1			; Turn off volume for the three sound channels
	MVO R1,_music_vol1
	MVO R1,_music_vol2
	NOP
	MVO R1,_music_vol3
	MVI _music_tc,R3
	DECR R3
	MVO R3,_music_tc
	BNE @@6
	; R3 is zero from here up to @@6
	MVI _music_p,R4
@@15:	TSTR R4		; Silence?
	BEQ @@000	; Keep quiet
	MVI@ R4,R0
	MVI@ R4,R1
	MVI _music_t,R2
        CMPI #$FE,R0	; The end?
	BEQ @@001       ; Keep quiet
	CMPI #$FD,R0	; Repeat?
	BNE @@00
	MVI _music_start,R4
	B @@15

@@001:	MOVR R1,R4	; Jump, zero will make it quiet
	B @@15

@@000:  MVII #1,R0
        MVO R0,_music_tc
        B @@0
        
@@00: 	MVO R2,_music_tc    ; Restart note time
     	MVO R4,_music_p
     	
	MOVR R0,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@1
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n1	; Note
	MVO R3,_music_s1	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i1	; Instrument
	
@@1:	MOVR R0,R2
	SWAP R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@2
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n2	; Note
	MVO R3,_music_s2	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i2	; Instrument
	
@@2:	MOVR R1,R2
	ANDI #$FF,R2
	CMPI #$3F,R2	; Sustain note?
	BEQ @@3
	MOVR R2,R4
	ANDI #$3F,R4
	MVO R4,_music_n3	; Note
	MVO R3,_music_s3	; Waveform
	ANDI #$C0,R2
	MVO R2,_music_i3	; Instrument
	
@@3:	MOVR R1,R2
	SWAP R2
	MVO R2,_music_n4
	MVO R3,_music_s4
	
        ;
        ; Construct main voice
        ;
@@6:	MVI _music_n1,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@7		; No, jump
	MVI _music_s1,R1
	MVI _music_i1,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq10	; Note in voice A
	SWAP R3
	MVO R3,_music_freq11
	MVO R1,_music_vol1
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@20
	SUBI #$08,R0
@@20:	MVO R0,_music_s1

@@7:	MVI _music_n2,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@8		; No, jump
	MVI _music_s2,R1
	MVI _music_i2,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq20	; Note in voice B
	SWAP R3
	MVO R3,_music_freq21
	MVO R1,_music_vol2
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@21
	SUBI #$08,R0
@@21:	MVO R0,_music_s2

@@8:	MVI _music_n3,R3	; Read note
	TSTR R3		; There is note?
	BEQ @@9		; No, jump
	MVI _music_s3,R1
	MVI _music_i3,R2
	MOVR R1,R0
	CALL _note2freq
	MVO R3,_music_freq30	; Note in voice C
	SWAP R3
	MVO R3,_music_freq31
	MVO R1,_music_vol3
        ; Increase time for instrument waveform
	INCR R0
	CMPI #$18,R0
	BNE @@22
	SUBI #$08,R0
@@22:	MVO R0,_music_s3

@@9:	MVI _music_n4,R0	; Read drum
	DECR R0		; There is drum?
	BMI @@4		; No, jump
	MVI _music_s4,R1
	       		; 1 - Strong
	BNE @@5
	CMPI #3,R1
	BGE @@12
@@10:	MVII #5,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@5:	DECR R0		;2 - Short
	BNE @@11
	TSTR R1
	BNE @@12
	MVII #8,R0
	MVO R0,_music_noise
	CALL _activate_drum
	B @@12

@@11:	;DECR R0	; 3 - Rolling
	;BNE @@12
	CMPI #2,R1
	BLT @@10
	MVI _music_t,R0
	SLR R0,1
	CMPR R0,R1
	BLT @@12
        ADDI #2,R0
	CMPR R0,R1
	BLT @@10
        ; Increase time for drum waveform
@@12:   INCR R1
	MVO R1,_music_s4
@@4:
@@0:	RETURN
	ENDP

        ;
	; Translates note number to frequency
        ; R3 = Note
        ; R1 = Position in waveform for instrument
        ; R2 = Instrument
        ;
_note2freq:	PROC
        ADD _music_table,R3
	MVI@ R3,R3
        SWAP R2
	BEQ _piano_instrument
	RLC R2,1
	BNC _clarinet_instrument
	BPL _flute_instrument
;	BMI _bass_instrument
	ENDP

        ;
        ; Generates a bass
        ;
_bass_instrument:	PROC
	SLL R3,2	; Lower 2 octaves
	ADDI #_bass_volume,R1
	MVI@ R1,R1	; Bass effect
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_bass_volume:	PROC
        DECLE 12,13,14,14,13,12,12,12
        DECLE 11,11,12,12,11,11,12,12
	DECLE 11,11,12,12,11,11,12,12
	ENDP

        ;
        ; Generates a piano
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency.
        ; R1 = Volume.
        ;
_piano_instrument:	PROC
	ADDI #_piano_volume,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_piano_volume:	PROC
        DECLE 14,13,13,12,12,11,11,10
        DECLE 10,9,9,8,8,7,7,6
        DECLE 6,6,7,7,6,6,5,5
	ENDP

        ;
        ; Generate a clarinet
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency
        ; R1 = Volume
        ;
_clarinet_instrument:	PROC
	ADDI #_clarinet_vibrato,R1
	ADD@ R1,R3
	CLRC
	RRC R3,1	; Duplicates frequency
	ADCR R3
        ADDI #_clarinet_volume-_clarinet_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_clarinet_vibrato:	PROC
        DECLE 0,0,0,0
        DECLE -2,-4,-2,0
        DECLE 2,4,2,0
        DECLE -2,-4,-2,0
        DECLE 2,4,2,0
        DECLE -2,-4,-2,0
	ENDP

_clarinet_volume:	PROC
        DECLE 13,14,14,13,13,12,12,12
        DECLE 11,11,11,11,12,12,12,12
        DECLE 11,11,11,11,12,12,12,12
	ENDP

        ;
        ; Generates a flute
        ; R3 = Frequency
        ; R1 = Waveform position
        ;
        ; Output:
        ; R3 = Frequency
        ; R1 = Volume
        ;
_flute_instrument:	PROC
	ADDI #_flute_vibrato,R1
	ADD@ R1,R3
	ADDI #_flute_volume-_flute_vibrato,R1
	MVI@ R1,R1
    IF DEFINED intybasic_music_volume
	B _global_volume
    ELSE
	JR R5
    ENDI
	ENDP

_flute_vibrato:	PROC
        DECLE 0,0,0,0
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
        DECLE 0,1,2,1
	ENDP
                 
_flute_volume:	PROC
        DECLE 10,12,13,13,12,12,12,12
        DECLE 11,11,11,11,10,10,10,10
        DECLE 11,11,11,11,10,10,10,10
	ENDP

    IF DEFINED intybasic_music_volume

_global_volume:	PROC
	MVI _music_vol,R2
	ANDI #$0F,R2
	SLL R2,2
	SLL R2,2
	ADDR R1,R2
	ADDI #@@table,R2
	MVI@ R2,R1
	JR R5

@@table:
	DECLE 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	DECLE 0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
	DECLE 0,0,0,0,1,1,1,1,1,1,1,2,2,2,2,2
	DECLE 0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3
	DECLE 0,0,1,1,1,1,2,2,2,2,3,3,3,4,4,4
	DECLE 0,0,1,1,1,2,2,2,3,3,3,4,4,4,5,5
	DECLE 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6
	DECLE 0,1,1,1,2,2,3,3,4,4,5,5,6,6,7,7
	DECLE 0,1,1,2,2,3,3,4,4,5,5,6,6,7,8,8
	DECLE 0,1,1,2,2,3,4,4,5,5,6,7,7,8,8,9
	DECLE 0,1,1,2,3,3,4,5,5,6,7,7,8,9,9,10
	DECLE 0,1,2,2,3,4,4,5,6,7,7,8,9,10,10,11
	DECLE 0,1,2,2,3,4,5,6,6,7,8,9,10,10,11,12
	DECLE 0,1,2,3,4,4,5,6,7,8,9,10,10,11,12,13
	DECLE 0,1,2,3,4,5,6,7,8,8,9,10,11,12,13,14
	DECLE 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

	ENDP

    ENDI

        ;
        ; Emits sound
        ;
_emit_sound:	PROC
        MOVR R5,R1
	MVI _music_mode,R2
	SARC R2,1
	BEQ @@6
	MVII #_music_freq10,R4
	MVII #$01F0,R5
        MVI@ R4,R0
	MVO@ R0,R5	; $01F0 - Channel A Period (Low 8 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F1 - Channel B Period (Low 8 bits of 12)
	DECR R2
	BEQ @@1
        MVI@ R4,R0	
	MVO@ R0,R5	; $01F2 - Channel C Period (Low 8 bits of 12)
	INCR R5		; Avoid $01F3 - Enveloped Period (Low 8 bits of 16)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F4 - Channel A Period (High 4 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F5 - Channel B Period (High 4 bits of 12)
        MVI@ R4,R0
	MVO@ R0,R5	; $01F6 - Channel C Period (High 4 bits of 12)
	INCR R5		; Avoid $01F7 - Envelope Period (High 8 bits of 16)
	BC @@2		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@3

@@2:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8 - Enable Noise/Tone (bits 3-5 Noise : 0-2 Tone)
        MVI@ R4,R0	
	MVO@ R0,R5	; $01F9 - Noise Period (5 bits)
	INCR R5		; Avoid $01FA - Envelope Type (4 bits)
@@3:    MVI@ R4,R0
	MVO@ R0,R5	; $01FB - Channel A Volume
        MVI@ R4,R0
	MVO@ R0,R5	; $01FC - Channel B Volume
        MVI@ R4,R0
	MVO@ R0,R5	; $01FD - Channel C Volume
        JR R1

@@1:	INCR R4		
	ADDI #2,R5	; Avoid $01F2 and $01F3
        MVI@ R4,R0
	MVO@ R0,R5	; $01F4
        MVI@ R4,R0
	MVO@ R0,R5	; $01F5
	INCR R4
	ADDI #2,R5	; Avoid $01F6 and $01F7
	BC @@4		; Jump if playing with drums
	ADDI #2,R4
	ADDI #3,R5
	B @@5

@@4:	MVI@ R4,R0
	MVO@ R0,R5	; $01F8
        MVI@ R4,R0
	MVO@ R0,R5	; $01F9
	INCR R5		; Avoid $01FA
@@5:    MVI@ R4,R0
	MVO@ R0,R5	; $01FB
        MVI@ R4,R0
	MVO@ R0,R5	; $01FD
@@6:    JR R1
	ENDP

        ;
        ; Activates drum
        ;
_activate_drum:	PROC
    IF DEFINED intybasic_music_volume
	BEGIN
    ENDI
	MVI _music_mode,R2
	SARC R2,1	; PLAY NO DRUMS?
	BNC @@0		; Yes, jump
	MVI _music_vol1,R0
	TSTR R0
	BNE @@1
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol1
	MVI _music_mix,R0
	ANDI #$F6,R0
	XORI #$01,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@1:    MVI _music_vol2,R0
	TSTR R0
	BNE @@2
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol2
	MVI _music_mix,R0
	ANDI #$ED,R0
	XORI #$02,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@2:    DECR R2		; PLAY SIMPLE?
        BEQ @@3		; Yes, jump
        MVI _music_vol3,R0
	TSTR R0
	BNE @@3
        MVII #11,R1
    IF DEFINED intybasic_music_volume
	CALL _global_volume
    ENDI
	MVO R1,_music_vol3
	MVI _music_mix,R0
	ANDI #$DB,R0
	XORI #$04,R0
	MVO R0,_music_mix
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

@@3:    MVI _music_mix,R0
        ANDI #$EF,R0
	MVO R0,_music_mix
@@0:	
    IF DEFINED intybasic_music_volume
	RETURN
    ELSE
	JR R5
    ENDI

	ENDP

    ENDI
    
    IF DEFINED intybasic_numbers

	;
	; Following code from as1600 libraries, prnum16.asm
        ; Public domain by Joseph Zbiciak
	;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  _PW10                                                                   ;;
;;      Lookup table holding the first 5 powers of 10 (1 thru 10000) as     ;;
;;      16-bit numbers.                                                     ;;
;; ======================================================================== ;;
_PW10   PROC    ; 0 thru 10000
        DECLE   10000, 1000, 100, 10, 1, 0
        ENDP

;; ======================================================================== ;;
;;  PRNUM16.l     -- Print an unsigned 16-bit number left-justified.        ;;
;;  PRNUM16.b     -- Print an unsigned 16-bit number with leading blanks.   ;;
;;  PRNUM16.z     -- Print an unsigned 16-bit number with leading zeros.    ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak  <im14u2c AT globalcrossing DOT net>                 ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      30-Mar-2003 Initial complete revision                               ;;
;;                                                                          ;;
;;  INPUTS for all variants                                                 ;;
;;      R0  Number to print.                                                ;;
;;      R2  Width of field.  Ignored by PRNUM16.l.                          ;;
;;      R3  Format word, added to digits to set the color.                  ;;
;;          Note:  Bit 15 MUST be cleared when building with PRNUM32.       ;;
;;      R4  Pointer to location on screen to print number                   ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0  Zeroed                                                          ;;
;;      R1  Unmodified                                                      ;;
;;      R2  Unmodified                                                      ;;
;;      R3  Unmodified                                                      ;;
;;      R4  Points to first character after field.                          ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      These routines print unsigned 16-bit numbers in a field up to 5     ;;
;;      positions wide.  The number is printed either in left-justified     ;;
;;      or right-justified format.  Right-justified numbers are padded      ;;
;;      with leading blanks or leading zeros.  Left-justified numbers       ;;
;;      are not padded on the right.                                        ;;
;;                                                                          ;;
;;      This code handles fields wider than 5 characters, padding with      ;;
;;      zeros or blanks as necessary.                                       ;;
;;                                                                          ;;
;;              Routine      Value(hex)     Field        Output             ;;
;;              ----------   ----------   ----------   ----------           ;;
;;              PRNUM16.l      $0045         n/a        "69"                ;;
;;              PRNUM16.b      $0045          4         "  69"              ;;
;;              PRNUM16.b      $0045          6         "    69"            ;;
;;              PRNUM16.z      $0045          4         "0069"              ;;
;;              PRNUM16.z      $0045          6         "000069"            ;;
;;                                                                          ;;
;;  TECHNIQUES                                                              ;;
;;      This routine uses repeated subtraction to divide the number         ;;
;;      to display by various powers of 10.  This is cheaper than a         ;;
;;      full divide, at least when the input number is large.  It's         ;;
;;      also easier to get right.  :-)                                      ;;
;;                                                                          ;;
;;      The printing routine first pads out fields wider than 5 spaces      ;;
;;      with zeros or blanks as requested.  It then scans the power-of-10   ;;
;;      table looking for the first power of 10 that is <= the number to    ;;
;;      display.  While scanning for this power of 10, it outputs leading   ;;
;;      blanks or zeros, if requested.  This eliminates "leading digit"     ;;
;;      logic from the main digit loop.                                     ;;
;;                                                                          ;;
;;      Once in the main digit loop, we discover the value of each digit    ;;
;;      by repeated subtraction.  We build up our digit value while         ;;
;;      subtracting the power-of-10 repeatedly.  We iterate until we go     ;;
;;      a step too far, and then we add back on power-of-10 to restore      ;;
;;      the remainder.                                                      ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      The left-justified variant ignores field width.                     ;;
;;                                                                          ;;
;;      The code is fully reentrant.                                        ;;
;;                                                                          ;;
;;      This code does not handle numbers which are too large to be         ;;
;;      displayed in the provided field.  If the number is too large,       ;;
;;      non-digit characters will be displayed in the initial digit         ;;
;;      position.  Also, the run time of this routine may get excessively   ;;
;;      large, depending on the magnitude of the overflow.                  ;;
;;                                                                          ;;
;;      When using with PRNUM32, one must either include PRNUM32 before     ;;
;;      this function, or define the symbol _WITH_PRNUM32.  PRNUM32         ;;
;;      needs a tiny bit of support from PRNUM16 to handle numbers in       ;;
;;      the range 65536...99999 correctly.                                  ;;
;;                                                                          ;;
;;  CODESIZE                                                                ;;
;;      73 words, including power-of-10 table                               ;;
;;      80 words, if compiled with PRNUM32.                                 ;;
;;                                                                          ;;
;;      To save code size, you can define the following symbols to omit     ;;
;;      some variants:                                                      ;;
;;                                                                          ;;
;;          _NO_PRNUM16.l:   Disables PRNUM16.l.  Saves 10 words            ;;
;;          _NO_PRNUM16.b:   Disables PRNUM16.b.  Saves 3 words.            ;;
;;                                                                          ;;
;;      Defining both symbols saves 17 words total, because it omits        ;;
;;      some code shared by both routines.                                  ;;
;;                                                                          ;;
;;  STACK USAGE                                                             ;;
;;      This function uses up to 4 words of stack space.                    ;;
;; ======================================================================== ;;

PRNUM16 PROC

    
        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.l:  Print unsigned, left-justified.                     ;;
        ;; ---------------------------------------------------------------- ;;
@@l:    PSHR    R5              ; save return address
@@l1:   MVII    #$1,    R5      ; set R5 to 1 to counteract screen ptr update
                                ; in the 'find initial power of 10' loop
        PSHR    R2
        MVII    #5,     R2      ; force effective field width to 5.
        B       @@z2

        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.b:  Print unsigned with leading blanks.                 ;;
        ;; ---------------------------------------------------------------- ;;
@@b:    PSHR    R5
@@b1:   CLRR    R5              ; let the blank loop do its thing
        INCR    PC              ; skip the PSHR R5

        ;; ---------------------------------------------------------------- ;;
        ;;  PRNUM16.z:  Print unsigned with leading zeros.                  ;;
        ;; ---------------------------------------------------------------- ;;
@@z:    PSHR    R5
@@z1:   PSHR    R2
@@z2:   PSHR    R1

        ;; ---------------------------------------------------------------- ;;
        ;;  Find the initial power of 10 to use for display.                ;;
        ;;  Note:  For fields wider than 5, fill the extra spots above 5    ;;
        ;;  with blanks or zeros as needed.                                 ;;
        ;; ---------------------------------------------------------------- ;;
        MVII    #_PW10+5,R1     ; Point to end of power-of-10 table
        SUBR    R2,     R1      ; Subtract the field width to get right power
        PSHR    R3              ; save format word

        CMPI    #2,     R5      ; are we leading with zeros?
        BNC     @@lblnk         ; no:  then do the loop w/ blanks

        CLRR    R5              ; force R5==0
        ADDI    #$80,   R3      ; yes: do the loop with zeros
        B       @@lblnk
    

@@llp   MVO@    R3,     R4      ; print a blank/zero

        SUBR    R5,     R4      ; rewind pointer if needed.

        INCR    R1              ; get next power of 10
@@lblnk DECR    R2              ; decrement available digits
        BEQ     @@ldone
        CMPI    #5,     R2      ; field too wide?
        BGE     @@llp           ; just force blanks/zeros 'till we're narrower.
        CMP@    R1,     R0      ; Is this power of 10 too big?
        BNC     @@llp           ; Yes:  Put a blank and go to next

@@ldone PULR    R3              ; restore format word

        ;; ---------------------------------------------------------------- ;;
        ;;  The digit loop prints at least one digit.  It discovers digits  ;;
        ;;  by repeated subtraction.                                        ;;
        ;; ---------------------------------------------------------------- ;;
@@digit TSTR    R0              ; If the number is zero, print zero and leave
        BNEQ    @@dig1          ; no: print the number

        MOVR    R3,     R5      ;\    
        ADDI    #$80,   R5      ; |-- print a 0 there.
        MVO@    R5,     R4      ;/    
        B       @@done

@@dig1:
    
@@nxdig MOVR    R3,     R5      ; save display format word
@@cont: ADDI    #$80-8, R5      ; start our digit as one just before '0'
@@spcl:
 
        ;; ---------------------------------------------------------------- ;;
        ;;  Divide by repeated subtraction.  This divide is constructed     ;;
        ;;  to go "one step too far" and then back up.                      ;;
        ;; ---------------------------------------------------------------- ;;
@@div:  ADDI    #8,     R5      ; increment our digit
        SUB@    R1,     R0      ; subtract power of 10
        BC      @@div           ; loop until we go too far
        ADD@    R1,     R0      ; add back the extra power of 10.

        MVO@    R5,     R4      ; display the digit.

        INCR    R1              ; point to next power of 10
        DECR    R2              ; any room left in field?
        BPL     @@nxdig         ; keep going until R2 < 0.

@@done: PULR    R1              ; restore R1
        PULR    R2              ; restore R2
        PULR    PC              ; return

        ENDP
        
    ENDI

    IF DEFINED intybasic_voice
;;==========================================================================;;
;;  SP0256-AL2 Allophones                                                   ;;
;;                                                                          ;;
;;  This file contains the allophone set that was obtained from an          ;;
;;  SP0256-AL2.  It is being provided for your convenience.                 ;;
;;                                                                          ;;
;;  The directory "al2" contains a series of assembly files, each one       ;;
;;  containing a single allophone.  This series of files may be useful in   ;;
;;  situations where space is at a premium.                                 ;;
;;                                                                          ;;
;;  Consult the Archer SP0256-AL2 documentation (under doc/programming)     ;;
;;  for more information about SP0256-AL2's allophone library.              ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                                                                          ;;
;;  Copyright information:                                                  ;;
;;                                                                          ;;
;;  The allophone data below was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is           ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY         ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.                                       ;;
;;                                                                          ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms        ;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.                                   ;;
;;                                                                          ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;                                                                          ;;
;;==========================================================================;;

;; ------------------------------------------------------------------------ ;;
_AA:
    DECLE   _AA.end - _AA - 1
    DECLE   $0318, $014C, $016F, $02CE, $03AF, $015F, $01B1, $008E
    DECLE   $0088, $0392, $01EA, $024B, $03AA, $039B, $000F, $0000
_AA.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_AE1:
    DECLE   _AE1.end - _AE1 - 1
    DECLE   $0118, $038E, $016E, $01FC, $0149, $0043, $026F, $036E
    DECLE   $01CC, $0005, $0000
_AE1.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AO:
    DECLE   _AO.end - _AO - 1
    DECLE   $0018, $010E, $016F, $0225, $00C6, $02C4, $030F, $0160
    DECLE   $024B, $0005, $0000
_AO.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AR:
    DECLE   _AR.end - _AR - 1
    DECLE   $0218, $010C, $016E, $001E, $000B, $0091, $032F, $00DE
    DECLE   $018B, $0095, $0003, $0238, $0027, $01E0, $03E8, $0090
    DECLE   $0003, $01C7, $0020, $03DE, $0100, $0190, $01CA, $02AB
    DECLE   $00B7, $004A, $0386, $0100, $0144, $02B6, $0024, $0320
    DECLE   $0011, $0041, $01DF, $0316, $014C, $016E, $001E, $00C4
    DECLE   $02B2, $031E, $0264, $02AA, $019D, $01BE, $000B, $00F0
    DECLE   $006A, $01CE, $00D6, $015B, $03B5, $03E4, $0000, $0380
    DECLE   $0007, $0312, $03E8, $030C, $016D, $02EE, $0085, $03C2
    DECLE   $03EC, $0283, $024A, $0005, $0000
_AR.end:  ; 69 decles
;; ------------------------------------------------------------------------ ;;
_AW:
    DECLE   _AW.end - _AW - 1
    DECLE   $0010, $01CE, $016E, $02BE, $0375, $034F, $0220, $0290
    DECLE   $008A, $026D, $013F, $01D5, $0316, $029F, $02E2, $018A
    DECLE   $0170, $0035, $00BD, $0000, $0000
_AW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_AX:
    DECLE   _AX.end - _AX - 1
    DECLE   $0218, $02CD, $016F, $02F5, $0386, $00C2, $00CD, $0094
    DECLE   $010C, $0005, $0000
_AX.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_AY:
    DECLE   _AY.end - _AY - 1
    DECLE   $0110, $038C, $016E, $03B7, $03B3, $02AF, $0221, $009E
    DECLE   $01AA, $01B3, $00BF, $02E7, $025B, $0354, $00DA, $017F
    DECLE   $018A, $03F3, $00AF, $02D5, $0356, $027F, $017A, $01FB
    DECLE   $011E, $01B9, $03E5, $029F, $025A, $0076, $0148, $0124
    DECLE   $003D, $0000
_AY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_BB1:
    DECLE   _BB1.end - _BB1 - 1
    DECLE   $0318, $004C, $016C, $00FB, $00C7, $0144, $002E, $030C
    DECLE   $010E, $018C, $01DC, $00AB, $00C9, $0268, $01F7, $021D
    DECLE   $01B3, $0098, $0000
_BB1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_BB2:
    DECLE   _BB2.end - _BB2 - 1
    DECLE   $00F4, $0046, $0062, $0200, $0221, $03E4, $0087, $016F
    DECLE   $02A6, $02B7, $0212, $0326, $0368, $01BF, $0338, $0196
    DECLE   $0002
_BB2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_CH:
    DECLE   _CH.end - _CH - 1
    DECLE   $00F5, $0146, $0052, $0000, $032A, $0049, $0032, $02F2
    DECLE   $02A5, $0000, $026D, $0119, $0124, $00F6, $0000
_CH.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_DD1:
    DECLE   _DD1.end - _DD1 - 1
    DECLE   $0318, $034C, $016E, $0397, $01B9, $0020, $02B1, $008E
    DECLE   $0349, $0291, $01D8, $0072, $0000
_DD1.end:  ; 13 decles
;; ------------------------------------------------------------------------ ;;
_DD2:
    DECLE   _DD2.end - _DD2 - 1
    DECLE   $00F4, $00C6, $00F2, $0000, $0129, $00A6, $0246, $01F3
    DECLE   $02C6, $02B7, $028E, $0064, $0362, $01CF, $0379, $01D5
    DECLE   $0002
_DD2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_DH1:
    DECLE   _DH1.end - _DH1 - 1
    DECLE   $0018, $034F, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_DH2:
    DECLE   _DH2.end - _DH2 - 1
    DECLE   $0119, $034C, $016D, $030B, $0306, $0363, $017E, $006A
    DECLE   $0164, $019E, $01DA, $00CB, $00E8, $027A, $03E8, $01D7
    DECLE   $0173, $00A1, $0000
_DH2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_EH:
    DECLE   _EH.end - _EH - 1
    DECLE   $0218, $02CD, $016F, $0105, $014B, $0224, $02CF, $0274
    DECLE   $014C, $0005, $0000
_EH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_EL:
    DECLE   _EL.end - _EL - 1
    DECLE   $0118, $038D, $016E, $011C, $008B, $03D2, $030F, $0262
    DECLE   $006C, $019D, $01CC, $022B, $0170, $0078, $03FE, $0018
    DECLE   $0183, $03A3, $010D, $016E, $012E, $00C6, $00C3, $0300
    DECLE   $0060, $000D, $0005, $0000
_EL.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_ER1:
    DECLE   _ER1.end - _ER1 - 1
    DECLE   $0118, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0188
    DECLE   $01DA, $00CB, $00E7, $0048, $03A6, $0244, $016C, $01A8
    DECLE   $03E4, $0000, $0002, $0001, $00FC, $01DA, $02E4, $0000
    DECLE   $0002, $0008, $0200, $0217, $0164, $0000, $000E, $0038
    DECLE   $0014, $01EA, $0264, $0000, $0002, $0048, $01EC, $02F1
    DECLE   $03CC, $016D, $021E, $0048, $00C2, $034E, $036A, $000D
    DECLE   $008D, $000B, $0200, $0047, $0022, $03A8, $0000, $0000
_ER1.end:  ; 64 decles
;; ------------------------------------------------------------------------ ;;
_ER2:
    DECLE   _ER2.end - _ER2 - 1
    DECLE   $0218, $034C, $016E, $001C, $0089, $01C3, $034E, $03E6
    DECLE   $00AB, $0095, $0001, $0000, $03FC, $0381, $0000, $0190
    DECLE   $01D8, $00CB, $00E7, $0058, $01A6, $0244, $0164, $02A9
    DECLE   $0024, $0000, $0000, $0007, $0201, $02F8, $02E4, $0000
    DECLE   $0002, $0001, $00FC, $02DA, $0024, $0000, $0002, $0008
    DECLE   $0200, $0217, $0024, $0000, $000E, $0038, $0014, $03EA
    DECLE   $03A4, $0000, $0002, $0048, $01EC, $03F1, $038C, $016D
    DECLE   $021E, $0048, $00C2, $034E, $036A, $000D, $009D, $0003
    DECLE   $0200, $0047, $0022, $03A8, $0000, $0000
_ER2.end:  ; 70 decles
;; ------------------------------------------------------------------------ ;;
_EY:
    DECLE   _EY.end - _EY - 1
    DECLE   $0310, $038C, $016E, $02A7, $00BB, $0160, $0290, $0094
    DECLE   $01CA, $03A9, $00C1, $02D7, $015B, $01D4, $03CE, $02FF
    DECLE   $00EA, $03E7, $0041, $0277, $025B, $0355, $03C9, $0103
    DECLE   $02EA, $03E4, $003F, $0000
_EY.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_FF:
    DECLE   _FF.end - _FF - 1
    DECLE   $0119, $03C8, $0000, $00A7, $0094, $0138, $01C6, $0000
_FF.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_GG1:
    DECLE   _GG1.end - _GG1 - 1
    DECLE   $00F4, $00C6, $00C2, $0200, $0015, $03FE, $0283, $01FD
    DECLE   $01E6, $00B7, $030A, $0364, $0331, $017F, $033D, $0215
    DECLE   $0002
_GG1.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG2:
    DECLE   _GG2.end - _GG2 - 1
    DECLE   $00F4, $0106, $0072, $0300, $0021, $0308, $0039, $0173
    DECLE   $00C6, $00B7, $037E, $03A3, $0319, $0177, $0036, $0217
    DECLE   $0002
_GG2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_GG3:
    DECLE   _GG3.end - _GG3 - 1
    DECLE   $00F8, $0146, $00F2, $0100, $0132, $03A8, $0055, $01F5
    DECLE   $00A6, $02B7, $0291, $0326, $0368, $0167, $023A, $01C6
    DECLE   $0002
_GG3.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_HH1:
    DECLE   _HH1.end - _HH1 - 1
    DECLE   $0218, $01C9, $0000, $0095, $0127, $0060, $01D6, $0213
    DECLE   $0002, $01AE, $033E, $01A0, $03C4, $0122, $0001, $0218
    DECLE   $01E4, $03FD, $0019, $0000
_HH1.end:  ; 20 decles
;; ------------------------------------------------------------------------ ;;
_HH2:
    DECLE   _HH2.end - _HH2 - 1
    DECLE   $0218, $00CB, $0000, $0086, $000F, $0240, $0182, $031A
    DECLE   $02DB, $0008, $0293, $0067, $00BD, $01E0, $0092, $000C
    DECLE   $0000
_HH2.end:  ; 17 decles
;; ------------------------------------------------------------------------ ;;
_IH:
    DECLE   _IH.end - _IH - 1
    DECLE   $0118, $02CD, $016F, $0205, $0144, $02C3, $00FE, $031A
    DECLE   $000D, $0005, $0000
_IH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_IY:
    DECLE   _IY.end - _IY - 1
    DECLE   $0318, $02CC, $016F, $0008, $030B, $01C3, $0330, $0178
    DECLE   $002B, $019D, $01F6, $018B, $01E1, $0010, $020D, $0358
    DECLE   $015F, $02A4, $02CC, $016F, $0109, $030B, $0193, $0320
    DECLE   $017A, $034C, $009C, $0017, $0001, $0200, $03C1, $0020
    DECLE   $00A7, $001D, $0001, $0104, $003D, $0040, $01A7, $01CA
    DECLE   $018B, $0160, $0078, $01F6, $0343, $01C7, $0090, $0000
_IY.end:  ; 48 decles
;; ------------------------------------------------------------------------ ;;
_JH:
    DECLE   _JH.end - _JH - 1
    DECLE   $0018, $0149, $0001, $00A4, $0321, $0180, $01F4, $039A
    DECLE   $02DC, $023C, $011A, $0047, $0200, $0001, $018E, $034E
    DECLE   $0394, $0356, $02C1, $010C, $03FD, $0129, $00B7, $01BA
    DECLE   $0000
_JH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_KK1:
    DECLE   _KK1.end - _KK1 - 1
    DECLE   $00F4, $00C6, $00D2, $0000, $023A, $03E0, $02D1, $02E5
    DECLE   $0184, $0200, $0041, $0210, $0188, $00C5, $0000
_KK1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_KK2:
    DECLE   _KK2.end - _KK2 - 1
    DECLE   $021D, $023C, $0211, $003C, $0180, $024D, $0008, $032B
    DECLE   $025B, $002D, $01DC, $01E3, $007A, $0000
_KK2.end:  ; 14 decles
;; ------------------------------------------------------------------------ ;;
_KK3:
    DECLE   _KK3.end - _KK3 - 1
    DECLE   $00F7, $0046, $01D2, $0300, $0131, $006C, $006E, $00F1
    DECLE   $00E4, $0000, $025A, $010D, $0110, $01F9, $014A, $0001
    DECLE   $00B5, $01A2, $00D8, $01CE, $0000
_KK3.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_LL:
    DECLE   _LL.end - _LL - 1
    DECLE   $0318, $038C, $016D, $029E, $0333, $0260, $0221, $0294
    DECLE   $01C4, $0299, $025A, $00E6, $014C, $012C, $0031, $0000
_LL.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_MM:
    DECLE   _MM.end - _MM - 1
    DECLE   $0210, $034D, $016D, $03F5, $00B0, $002E, $0220, $0290
    DECLE   $03CE, $02B6, $03AA, $00F3, $00CF, $015D, $016E, $0000
_MM.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_NG1:
    DECLE   _NG1.end - _NG1 - 1
    DECLE   $0118, $03CD, $016E, $00DC, $032F, $01BF, $01E0, $0116
    DECLE   $02AB, $029A, $0358, $01DB, $015B, $01A7, $02FD, $02B1
    DECLE   $03D2, $0356, $0000
_NG1.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_NN1:
    DECLE   _NN1.end - _NN1 - 1
    DECLE   $0318, $03CD, $016C, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $009D, $000D, $0248, $01B4, $0120, $01E1, $00C8
    DECLE   $0003, $0040, $0000, $0080, $015F, $0006, $0000
_NN1.end:  ; 23 decles
;; ------------------------------------------------------------------------ ;;
_NN2:
    DECLE   _NN2.end - _NN2 - 1
    DECLE   $0018, $034D, $016D, $0203, $0306, $03C3, $015F, $0270
    DECLE   $002A, $0095, $0003, $0248, $01B4, $0120, $01E1, $0090
    DECLE   $000B, $0040, $0000, $0080, $015F, $019E, $01F6, $028B
    DECLE   $00E0, $0266, $03F6, $01D8, $0143, $01A8, $0024, $00C0
    DECLE   $0080, $0000, $01E6, $0321, $0024, $0260, $000A, $0008
    DECLE   $03FE, $0000, $0000
_NN2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_OR2:
    DECLE   _OR2.end - _OR2 - 1
    DECLE   $0218, $018C, $016D, $02A6, $03AB, $004F, $0301, $0390
    DECLE   $02EA, $0289, $0228, $0356, $01CF, $02D5, $0135, $007D
    DECLE   $02B5, $02AF, $024A, $02E2, $0153, $0167, $0333, $02A9
    DECLE   $02B3, $039A, $0351, $0147, $03CD, $0339, $02DA, $0000
_OR2.end:  ; 32 decles
;; ------------------------------------------------------------------------ ;;
_OW:
    DECLE   _OW.end - _OW - 1
    DECLE   $0310, $034C, $016E, $02AE, $03B1, $00CF, $0304, $0192
    DECLE   $018A, $022B, $0041, $0277, $015B, $0395, $03D1, $0082
    DECLE   $03CE, $00B6, $03BB, $02DA, $0000
_OW.end:  ; 21 decles
;; ------------------------------------------------------------------------ ;;
_OY:
    DECLE   _OY.end - _OY - 1
    DECLE   $0310, $014C, $016E, $02A6, $03AF, $00CF, $0304, $0192
    DECLE   $03CA, $01A8, $007F, $0155, $02B4, $027F, $00E2, $036A
    DECLE   $031F, $035D, $0116, $01D5, $02F4, $025F, $033A, $038A
    DECLE   $014F, $01B5, $03D5, $0297, $02DA, $03F2, $0167, $0124
    DECLE   $03FB, $0001
_OY.end:  ; 34 decles
;; ------------------------------------------------------------------------ ;;
_PA1:
    DECLE   _PA1.end - _PA1 - 1
    DECLE   $00F1, $0000
_PA1.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA2:
    DECLE   _PA2.end - _PA2 - 1
    DECLE   $00F4, $0000
_PA2.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA3:
    DECLE   _PA3.end - _PA3 - 1
    DECLE   $00F7, $0000
_PA3.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA4:
    DECLE   _PA4.end - _PA4 - 1
    DECLE   $00FF, $0000
_PA4.end:  ; 2 decles
;; ------------------------------------------------------------------------ ;;
_PA5:
    DECLE   _PA5.end - _PA5 - 1
    DECLE   $031D, $003F, $0000
_PA5.end:  ; 3 decles
;; ------------------------------------------------------------------------ ;;
_PP:
    DECLE   _PP.end - _PP - 1
    DECLE   $00FD, $0106, $0052, $0000, $022A, $03A5, $0277, $035F
    DECLE   $0184, $0000, $0055, $0391, $00EB, $00CF, $0000
_PP.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_RR1:
    DECLE   _RR1.end - _RR1 - 1
    DECLE   $0118, $01CD, $016C, $029E, $0171, $038E, $01E0, $0190
    DECLE   $0245, $0299, $01AA, $02E2, $01C7, $02DE, $0125, $00B5
    DECLE   $02C5, $028F, $024E, $035E, $01CB, $02EC, $0005, $0000
_RR1.end:  ; 24 decles
;; ------------------------------------------------------------------------ ;;
_RR2:
    DECLE   _RR2.end - _RR2 - 1
    DECLE   $0218, $03CC, $016C, $030C, $02C8, $0393, $02CD, $025E
    DECLE   $008A, $019D, $01AC, $02CB, $00BE, $0046, $017E, $01C2
    DECLE   $0174, $00A1, $01E5, $00E0, $010E, $0007, $0313, $0017
    DECLE   $0000
_RR2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SH:
    DECLE   _SH.end - _SH - 1
    DECLE   $0218, $0109, $0000, $007A, $0187, $02E0, $03F6, $0311
    DECLE   $0002, $0126, $0242, $0161, $03E9, $0219, $016C, $0300
    DECLE   $0013, $0045, $0124, $0005, $024C, $005C, $0182, $03C2
    DECLE   $0001
_SH.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_SS:
    DECLE   _SS.end - _SS - 1
    DECLE   $0218, $01CA, $0001, $0128, $001C, $0149, $01C6, $0000
_SS.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TH:
    DECLE   _TH.end - _TH - 1
    DECLE   $0019, $0349, $0000, $00C6, $0212, $01D8, $01CA, $0000
_TH.end:  ; 8 decles
;; ------------------------------------------------------------------------ ;;
_TT1:
    DECLE   _TT1.end - _TT1 - 1
    DECLE   $00F6, $0046, $0142, $0100, $0042, $0088, $027E, $02EF
    DECLE   $01A4, $0200, $0049, $0290, $00FC, $00E8, $0000
_TT1.end:  ; 15 decles
;; ------------------------------------------------------------------------ ;;
_TT2:
    DECLE   _TT2.end - _TT2 - 1
    DECLE   $00F5, $00C6, $01D2, $0100, $0335, $00E9, $0042, $027A
    DECLE   $02A4, $0000, $0062, $01D1, $014C, $03EA, $02EC, $01E0
    DECLE   $0007, $03A7, $0000
_TT2.end:  ; 19 decles
;; ------------------------------------------------------------------------ ;;
_UH:
    DECLE   _UH.end - _UH - 1
    DECLE   $0018, $034E, $016E, $01FF, $0349, $00D2, $003C, $030C
    DECLE   $008B, $0005, $0000
_UH.end:  ; 11 decles
;; ------------------------------------------------------------------------ ;;
_UW1:
    DECLE   _UW1.end - _UW1 - 1
    DECLE   $0318, $014C, $016F, $029E, $03BD, $03BD, $0271, $0212
    DECLE   $0325, $0291, $016A, $027B, $014A, $03B4, $0133, $0001
_UW1.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_UW2:
    DECLE   _UW2.end - _UW2 - 1
    DECLE   $0018, $034E, $016E, $02F6, $0107, $02C2, $006D, $0090
    DECLE   $03AC, $01A4, $01DC, $03AB, $0128, $0076, $03E6, $0119
    DECLE   $014F, $03A6, $03A5, $0020, $0090, $0001, $02EE, $00BB
    DECLE   $0000
_UW2.end:  ; 25 decles
;; ------------------------------------------------------------------------ ;;
_VV:
    DECLE   _VV.end - _VV - 1
    DECLE   $0218, $030D, $016C, $010B, $010B, $0095, $034F, $03E4
    DECLE   $0108, $01B5, $01BE, $028B, $0160, $00AA, $03E4, $0106
    DECLE   $00EB, $02DE, $014C, $016E, $00F6, $0107, $00D2, $00CD
    DECLE   $0296, $00E4, $0006, $0000
_VV.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_WH:
    DECLE   _WH.end - _WH - 1
    DECLE   $0218, $00C9, $0000, $0084, $038E, $0147, $03A4, $0195
    DECLE   $0000, $012E, $0118, $0150, $02D1, $0232, $01B7, $03F1
    DECLE   $0237, $01C8, $03B1, $0227, $01AE, $0254, $0329, $032D
    DECLE   $01BF, $0169, $019A, $0307, $0181, $028D, $0000
_WH.end:  ; 31 decles
;; ------------------------------------------------------------------------ ;;
_WW:
    DECLE   _WW.end - _WW - 1
    DECLE   $0118, $034D, $016C, $00FA, $02C7, $0072, $03CC, $0109
    DECLE   $000B, $01AD, $019E, $016B, $0130, $0278, $01F8, $0314
    DECLE   $017E, $029E, $014D, $016D, $0205, $0147, $02E2, $001A
    DECLE   $010A, $026E, $0004, $0000
_WW.end:  ; 28 decles
;; ------------------------------------------------------------------------ ;;
_XR2:
    DECLE   _XR2.end - _XR2 - 1
    DECLE   $0318, $034C, $016E, $02A6, $03BB, $002F, $0290, $008E
    DECLE   $004B, $0392, $01DA, $024B, $013A, $01DA, $012F, $00B5
    DECLE   $02E5, $0297, $02DC, $0372, $014B, $016D, $0377, $00E7
    DECLE   $0376, $038A, $01CE, $026B, $02FA, $01AA, $011E, $0071
    DECLE   $00D5, $0297, $02BC, $02EA, $01C7, $02D7, $0135, $0155
    DECLE   $01DD, $0007, $0000
_XR2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_YR:
    DECLE   _YR.end - _YR - 1
    DECLE   $0318, $03CC, $016E, $0197, $00FD, $0130, $0270, $0094
    DECLE   $0328, $0291, $0168, $007E, $01CC, $02F5, $0125, $02B5
    DECLE   $00F4, $0298, $01DA, $03F6, $0153, $0126, $03B9, $00AB
    DECLE   $0293, $03DB, $0175, $01B9, $0001
_YR.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY1:
    DECLE   _YY1.end - _YY1 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0001, $0000
_YY1.end:  ; 29 decles
;; ------------------------------------------------------------------------ ;;
_YY2:
    DECLE   _YY2.end - _YY2 - 1
    DECLE   $0318, $01CC, $016E, $0015, $00CB, $0263, $0320, $0078
    DECLE   $01CE, $0094, $001F, $0040, $0320, $03BF, $0230, $00A7
    DECLE   $000F, $01FE, $03FC, $01E2, $00D0, $0089, $000F, $0248
    DECLE   $032B, $03FD, $01CF, $0199, $01EE, $008B, $0161, $0232
    DECLE   $0004, $0318, $01A7, $0198, $0124, $03E0, $0001, $0001
    DECLE   $030F, $0027, $0000
_YY2.end:  ; 43 decles
;; ------------------------------------------------------------------------ ;;
_ZH:
    DECLE   _ZH.end - _ZH - 1
    DECLE   $0310, $014D, $016E, $00C3, $03B9, $01BF, $0241, $0012
    DECLE   $0163, $00E1, $0000, $0080, $0084, $023F, $003F, $0000
_ZH.end:  ; 16 decles
;; ------------------------------------------------------------------------ ;;
_ZZ:
    DECLE   _ZZ.end - _ZZ - 1
    DECLE   $0218, $010D, $016F, $0225, $0351, $00B5, $02A0, $02EE
    DECLE   $00E9, $014D, $002C, $0360, $0008, $00EC, $004C, $0342
    DECLE   $03D4, $0156, $0052, $0131, $0008, $03B0, $01BE, $0172
    DECLE   $0000
_ZZ.end:  ; 25 decles

;;==========================================================================;;
;;                                                                          ;;
;;  Copyright information:                                                  ;;
;;                                                                          ;;
;;  The above allophone data was extracted from the SP0256-AL2 ROM image.   ;;
;;  The SP0256-AL2 allophones are NOT in the public domain, nor are they    ;;
;;  placed under the GNU General Public License.  This program is           ;;
;;  distributed in the hope that it will be useful, but WITHOUT ANY         ;;
;;  WARRANTY; without even the implied warranty of MERCHANTABILITY or       ;;
;;  FITNESS FOR A PARTICULAR PURPOSE.                                       ;;
;;                                                                          ;;
;;  Microchip, Inc. retains the copyright to the data and algorithms        ;;
;;  contained in the SP0256-AL2.  This speech data is distributed with      ;;
;;  explicit permission from Microchip, Inc.  All such redistributions      ;;
;;  must retain this notice of copyright.                                   ;;
;;                                                                          ;;
;;  No copyright claims are made on this data by the author(s) of SDK1600.  ;;
;;  Please see http://spatula-city.org/~im14u2c/sp0256-al2/ for details.    ;;
;;                                                                          ;;
;;==========================================================================;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  INTELLIVOICE DRIVER ROUTINES                                            ;;
;;  Written in 2002 by Joe Zbiciak <intvnut AT gmail.com>                   ;;
;;  http://spatula-city.org/~im14u2c/intv/                                  ;;
;; ======================================================================== ;;

;; ======================================================================== ;;
;;  GLOBAL VARIABLES USED BY THESE ROUTINES                                 ;;
;;                                                                          ;;
;;  Note that some of these routines may use one or more global variables.  ;;
;;  If you use these routines, you will need to allocate the appropriate    ;;
;;  space in either 16-bit or 8-bit memory as appropriate.  Each global     ;;
;;  variable is listed with the routines which use it and the required      ;;
;;  memory width.                                                           ;;
;;                                                                          ;;
;;  Example declarations for these routines are shown below, commented out. ;;
;;  You should uncomment these and add them to your program to make use of  ;;
;;  the routine that needs them.  Make sure to assign these variables to    ;;
;;  locations that aren't used for anything else.                           ;;
;; ======================================================================== ;;

                        ; Used by       Req'd Width     Description
                        ;-----------------------------------------------------
;IV.QH      EQU $110    ; IV_xxx        8-bit           Voice queue head
;IV.QT      EQU $111    ; IV_xxx        8-bit           Voice queue tail
;IV.Q       EQU $112    ; IV_xxx        8-bit           Voice queue  (8 bytes)
;IV.FLEN    EQU $11A    ; IV_xxx        8-bit           Length of FIFO data
;IV.FPTR    EQU $320    ; IV_xxx        16-bit          Current FIFO ptr.
;IV.PPTR    EQU $321    ; IV_xxx        16-bit          Current Phrase ptr.

;; ======================================================================== ;;
;;  MEMORY USAGE                                                            ;;
;;                                                                          ;;
;;  These routines implement a queue of "pending phrases" that will be      ;;
;;  played by the Intellivoice.  The user calls IV_PLAY to enqueue a        ;;
;;  phrase number.  Phrase numbers indicate either a RESROM sample or       ;;
;;  a compiled in phrase to be spoken.                                      ;;
;;                                                                          ;;
;;  The user must compose an "IV_PHRASE_TBL", which is composed of          ;;
;;  pointers to phrases to be spoken.  Phrases are strings of pointers      ;;
;;  and RESROM triggers, terminated by a NUL.                               ;;
;;                                                                          ;;
;;  Phrase numbers 1 through 42 are RESROM samples.  Phrase numbers         ;;
;;  43 through 255 index into the IV_PHRASE_TBL.                            ;;
;;                                                                          ;;
;;  SPECIAL NOTES                                                           ;;
;;                                                                          ;;
;;  Bit 7 of IV.QH and IV.QT is used to denote whether the Intellivoice     ;;
;;  is present.  If Intellivoice is present, this bit is clear.             ;;
;;                                                                          ;;
;;  Bit 6 of IV.QT is used to denote that we still need to do an ALD $00    ;;
;;  for FIFO'd voice data.                                                  ;;
;; ======================================================================== ;;
            

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_INIT     Initialize the Intellivoice                             ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_INIT                                                      ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0      0 if Intellivoice found, -1 if not.                         ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      Resets Intellivoice, determines if it is actually there, and        ;;
;;      then initializes the IV structure.                                  ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;

IV_INIT     PROC
            MVII    #$0400, R0          ;
            MVO     R0,     $0081       ; Reset the Intellivoice

            MVI     $0081,  R0          ; \
            RLC     R0,     2           ;  |-- See if we detect Intellivoice
            BOV     @@no_ivoice         ; /    once we've reset it.

            CLRR    R0                  ; 
            MVO     R0,     IV.FPTR     ; No data for FIFO
            MVO     R0,     IV.PPTR     ; No phrase being spoken
            MVO     R0,     IV.QH       ; Clear our queue
            MVO     R0,     IV.QT       ; Clear our queue
            JR      R5                  ; Done!

@@no_ivoice:
            CLRR    R0
            MVO     R0,     IV.FPTR     ; No data for FIFO
            MVO     R0,     IV.PPTR     ; No phrase being spoken
            DECR    R0
            MVO     R0,     IV.QH       ; Set queue to -1 ("No Intellivoice")
            MVO     R0,     IV.QT       ; Set queue to -1 ("No Intellivoice")
            JR      R5                  ; Done!
            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_ISR      Interrupt service routine to feed Intellivoice          ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_ISR                                                       ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1, R4 trashed.                                                 ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      Call this from your main interrupt service routine.                 ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_ISR      PROC
            ;; ------------------------------------------------------------ ;;
            ;;  Check for Intellivoice.  Leave if none present.             ;;
            ;; ------------------------------------------------------------ ;;
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2
            BPL     @@ok                ; Bit 7 set? If yes: No Intellivoice
@@ald_busy:
@@leave     JR      R5                  ; Exit if no Intellivoice.

     
            ;; ------------------------------------------------------------ ;;
            ;;  Check to see if we pump samples into the FIFO.
            ;; ------------------------------------------------------------ ;;
@@ok:       MVI     IV.FPTR, R4         ; Get FIFO data pointer
            TSTR    R4                  ; is it zero?
            BEQ     @@no_fifodata       ; Yes:  No data for FIFO.
@@fifo_fill:
            MVI     $0081,  R0          ; Read speech FIFO ready bit
            SLLC    R0,     1           ; 
            BC      @@fifo_busy     

            MVI@    R4,     R0          ; Get next word
            MVO     R0,     $0081       ; write it to the FIFO

            MVI     IV.FLEN, R0         ;\
            DECR    R0                  ; |-- Decrement our FIFO'd data length
            MVO     R0,     IV.FLEN     ;/
            BEQ     @@last_fifo         ; If zero, we're done w/ FIFO
            MVO     R4,     IV.FPTR     ; Otherwise, save new pointer
            B       @@fifo_fill         ; ...and keep trying to load FIFO

@@last_fifo MVO     R0,     IV.FPTR     ; done with FIFO loading.
                                        ; fall into ALD processing.


            ;; ------------------------------------------------------------ ;;
            ;;  Try to do an Address Load.  We do this in two settings:     ;;
            ;;   -- We have no FIFO data to load.                           ;;
            ;;   -- We've loaded as much FIFO data as we can, but we        ;;
            ;;      might have an address load command to send for it.      ;;
            ;; ------------------------------------------------------------ ;;
@@fifo_busy:
@@no_fifodata:
            MVI     $0080,  R0          ; Read LRQ bit from ALD register
            SLLC    R0,     1
            BNC     @@ald_busy          ; LRQ is low, meaning we can't ALD.
                                        ; So, leave.

            ;; ------------------------------------------------------------ ;;
            ;;  We can do an address load (ALD) on the SP0256.  Give FIFO   ;;
            ;;  driven ALDs priority, since we already started the FIFO     ;;
            ;;  load.  The "need ALD" bit is stored in bit 6 of IV.QT.      ;;
            ;; ------------------------------------------------------------ ;;
            ANDI    #$40,   R1          ; Is "Need FIFO ALD" bit set?
            BEQ     @@no_fifo_ald
            XOR     IV.QT,  R1          ;\__ Clear the "Need FIFO ALD" bit.
            MVO     R1,     IV.QT       ;/
            CLRR    R1
            MVO     R1,     $80         ; Load a 0 into ALD (trigger FIFO rd.)
            JR      R5                  ; done!

            ;; ------------------------------------------------------------ ;;
            ;;  We don't need to ALD on behalf of the FIFO.  So, we grab    ;;
            ;;  the next thing off our phrase list.                         ;;
            ;; ------------------------------------------------------------ ;;
@@no_fifo_ald:
            MVI     IV.PPTR, R4         ; Get phrase pointer.
            TSTR    R4                  ; Is it zero?
            BEQ     @@next_phrase       ; Yes:  Get next phrase from queue.

            MVI@    R4,     R0
            TSTR    R0                  ; Is it end of phrase?
            BNEQ    @@process_phrase    ; !=0:  Go do it.

            MVO     R0,     IV.PPTR     ; 
@@next_phrase:
            MVI     IV.QT,  R1          ; reload queue tail (was trashed above)
            MOVR    R1,     R0          ; copy QT to R0 so we can increment it
            ANDI    #$7,    R1          ; Mask away flags in queue head
            CMP     IV.QH,  R1          ; Is it same as queue tail?
            BEQ     @@leave             ; Yes:  No more speech for now.

            INCR    R0
            ANDI    #$F7,   R0          ; mask away the possible 'carry'
            MVO     R0,     IV.QT       ; save updated queue tail

            ADDI    #IV.Q,  R1          ; Index into queue
            MVI@    R1,     R4          ; get next value from queue
            CMPI    #43,    R4          ; Is it a RESROM or Phrase?
            BNC     @@play_resrom_r4
@@new_phrase:
;            ADDI    #IV_PHRASE_TBL - 43, R4 ; Index into phrase table
;            MVI@    R4,     R4          ; Read from phrase table
            MVO     R4,     IV.PPTR
            JR      R5                  ; we'll get to this phrase next time.

@@play_resrom_r4:
            MVO     R4,     $0080       ; Just ALD it
            JR      R5                  ; and leave.

            ;; ------------------------------------------------------------ ;;
            ;;  We're in the middle of a phrase, so continue interpreting.  ;;
            ;; ------------------------------------------------------------ ;;
@@process_phrase:
            
            MVO     R4,     IV.PPTR     ; save new phrase pointer
            CMPI    #43,    R0          ; Is it a RESROM cue?
            BC      @@play_fifo         ; Just ALD it and leave.
@@play_resrom_r0
            MVO     R0,     $0080       ; Just ALD it
            JR      R5                  ; and leave.
@@play_fifo:
            MVI     IV.FPTR,R1          ; Make sure not to stomp existing FIFO
            TSTR    R1                  ; data.
            BEQ     @@new_fifo_ok
            DECR    R4                  ; Oops, FIFO data still playing,
            MVO     R4,     IV.PPTR     ; so rewind.
            JR      R5                  ; and leave.

@@new_fifo_ok:
            MOVR    R0,     R4          ;
            MVI@    R4,     R0          ; Get chunk length
            MVO     R0,     IV.FLEN     ; Init FIFO chunk length
            MVO     R4,     IV.FPTR     ; Init FIFO pointer
            MVI     IV.QT,  R0          ;\
            XORI    #$40,   R0          ; |- Set "Need ALD" bit in QT
            MVO     R0,     IV.QT       ;/

  IF 1      ; debug code                ;\
            ANDI    #$40,   R0          ; |   Debug code:  We should only
            BNEQ    @@qtok              ; |-- be here if "Need FIFO ALD" 
            HLT     ;BUG!!              ; |   was already clear.         
@@qtok                                  ;/    
  ENDI
            JR      R5                  ; leave.

            ENDP


;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_PLAY     Play a voice sample sequence.                           ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY                                                      ;;
;;      R5      Invocation record, followed by return address.              ;;
;;                  1 DECLE    Phrase number to play.                       ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY.1                                                    ;;
;;      R0      Address of phrase to play.                                  ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1  trashed                                                     ;;
;;      Z==0    if item not successfully queued.                            ;;
;;      Z==1    if successfully queued.                                     ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code will drop phrases if the queue is full.                   ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index        ;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the         ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_PLAY     PROC
            MVI@    R5,     R0

@@1:        ; alternate entry point
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2           ;\___ Leave if "no Intellivoice"
            BMI     @@leave             ;/    bit it set.
@@ok:       
            DECR    R1                  ;\
            ANDI    #$7,    R1          ; |-- See if we still have room
            CMP     IV.QH,  R1          ;/
            BEQ     @@leave             ; Leave if we're full

@@2:        MVI     IV.QH,  R1          ; Get our queue head pointer
            PSHR    R1                  ;\
            INCR    R1                  ; |
            ANDI    #$F7,   R1          ; |-- Increment it, removing
            MVO     R1,     IV.QH       ; |   carry but preserving flags.
            PULR    R1                  ;/

            ADDI    #IV.Q,  R1          ;\__ Store phrase to queue
            MVO@    R0,     R1          ;/

@@leave:    JR      R5                  ; Leave.
            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_PLAYW    Play a voice sample sequence.  Wait for queue room.     ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY                                                      ;;
;;      R5      Invocation record, followed by return address.              ;;
;;                  1 DECLE    Phrase number to play.                       ;;
;;                                                                          ;;
;;  INPUTS for IV_PLAY.1                                                    ;;
;;      R0      Address of phrase to play.                                  ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0, R1  trashed                                                     ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code will wait for a queue slot to open if queue is full.      ;;
;;      Phrase numbers 1..42 are RESROM samples.  43..255 will index        ;;
;;      into the user-supplied IV_PHRASE_TBL.  43 will refer to the         ;;
;;      first entry, 44 to the second, and so on.  Phrase 0 is undefined.   ;;
;;                                                                          ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_PLAYW    PROC
            MVI@    R5,     R0

@@1:        ; alternate entry point
            MVI     IV.QT,  R1          ; Get queue tail
            SWAP    R1,     2           ;\___ Leave if "no Intellivoice"
            BMI     IV_PLAY.leave       ;/    bit it set.
@@ok:       
            DECR    R1                  ;\
            ANDI    #$7,    R1          ; |-- See if we still have room
            CMP     IV.QH,  R1          ;/
            BEQ     @@1                 ; wait for room
            B       IV_PLAY.2

            ENDP

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_WAIT     Wait for voice queue to empty.                          ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      15-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_WAIT                                                      ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;      R0      trashed.                                                    ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This waits until the Intellivoice is nearly completely quiescent.   ;;
;;      Some voice data may still be spoken from the last triggered         ;;
;;      phrase.  To truly wait for *that* to be spoken, speak a 'pause'     ;;
;;      (eg. RESROM.pa1) and then call IV_WAIT.                             ;;
;; ------------------------------------------------------------------------ ;;
;;                   Copyright (c) 2002, Joseph Zbiciak                     ;;
;; ======================================================================== ;;
IV_WAIT     PROC
            MVI     IV.QH,  R0
            SWAP    R0                  ;\___ test bit 7, leave if set.
            SWAP    R0                  ;/    (SWAP2 corrupts upper byte.)
            BMI     @@leave

            ; Wait for queue to drain.
@@q_loop:   CMP     IV.QT,  R0
            BNEQ    @@q_loop

            ; Wait for FIFO and LRQ to say ready.
@@s_loop:   MVI     $81,    R0          ; Read FIFO status.  0 == ready.
            COMR    R0
            AND     $80,    R0          ; Merge w/ ALD status.  1 == ready
            TSTR    R0
            BPL     @@s_loop            ; if bit 15 == 0, not ready.
            
@@leave:    JR      R5
            ENDP

;; ======================================================================== ;;
;;  End of File:  ivoice.asm                                                ;;
;; ======================================================================== ;;

;* ======================================================================== *;
;*  These routines are placed into the public domain by their author.  All  *;
;*  copyright rights are hereby relinquished on the routines and data in    *;
;*  this file.  -- Joseph Zbiciak, 2008                                     *;
;* ======================================================================== *;

;; ======================================================================== ;;
;;  NAME                                                                    ;;
;;      IV_SAYNUM16 Say a 16-bit unsigned number using RESROM digits        ;;
;;                                                                          ;;
;;  AUTHOR                                                                  ;;
;;      Joseph Zbiciak <intvnut AT gmail.com>                               ;;
;;                                                                          ;;
;;  REVISION HISTORY                                                        ;;
;;      16-Sep-2002 Initial revision . . . . . . . . . . .  J. Zbiciak      ;;
;;                                                                          ;;
;;  INPUTS for IV_INIT                                                      ;;
;;      R0      Number to "speak"                                           ;;
;;      R5      Return address                                              ;;
;;                                                                          ;;
;;  OUTPUTS                                                                 ;;
;;                                                                          ;;
;;  DESCRIPTION                                                             ;;
;;      "Says" a 16-bit number using IV_PLAYW to queue up the phrase.       ;;
;;      Because the number may be built from several segments, it could     ;;
;;      easily eat up the queue.  I believe the longest number will take    ;;
;;      7 queue entries -- that is, fill the queue.  Thus, this code        ;;
;;      could block, waiting for slots in the queue.                        ;;
;; ======================================================================== ;;

IV_SAYNUM16 PROC
            PSHR    R5

            TSTR    R0
            BEQ     @@zero          ; Special case:  Just say "zero"

            ;; ------------------------------------------------------------ ;;
            ;;  First, try to pull off 'thousands'.  We call ourselves      ;;
            ;;  recursively to play the the number of thousands.            ;;
            ;; ------------------------------------------------------------ ;;
            CLRR    R1
@@thloop:   INCR    R1
            SUBI    #1000,  R0
            BC      @@thloop

            ADDI    #1000,  R0
            PSHR    R0
            DECR    R1
            BEQ     @@no_thousand

            CALL    IV_SAYNUM16.recurse

            CALL    IV_PLAYW
            DECLE   36  ; THOUSAND
            
@@no_thousand
            PULR    R1

            ;; ------------------------------------------------------------ ;;
            ;;  Now try to play hundreds.                                   ;;
            ;; ------------------------------------------------------------ ;;
            MVII    #7-1, R0    ; ZERO
            CMPI    #100,   R1
            BNC     @@no_hundred

@@hloop:    INCR    R0
            SUBI    #100,   R1
            BC      @@hloop
            ADDI    #100,   R1

            PSHR    R1

            CALL    IV_PLAYW.1

            CALL    IV_PLAYW
            DECLE   35  ; HUNDRED

            PULR    R1
            B       @@notrecurse    ; skip "PSHR R5"
@@recurse:  PSHR    R5              ; recursive entry point for 'thousand'

@@no_hundred:
@@notrecurse:
            MOVR    R1,     R0
            BEQ     @@leave

            SUBI    #20,    R1
            BNC     @@teens

            MVII    #27-1, R0   ; TWENTY
@@tyloop    INCR    R0
            SUBI    #10,    R1
            BC      @@tyloop
            ADDI    #10,    R1

            PSHR    R1
            CALL    IV_PLAYW.1

            PULR    R0
            TSTR    R0
            BEQ     @@leave

@@teens:
@@zero:     ADDI    #7, R0  ; ZERO

            CALL    IV_PLAYW.1

@@leave     PULR    PC
            ENDP

;; ======================================================================== ;;
;;  End of File:  saynum16.asm                                              ;;
;; ======================================================================== ;;

    ENDI

        IF DEFINED intybasic_flash

;; ======================================================================== ;;
;;  JLP "Save Game" support                                                 ;;
;; ======================================================================== ;;
JF.first    EQU     $8023
JF.last     EQU     $8024
JF.addr     EQU     $8025
JF.row      EQU     $8026
                   
JF.wrcmd    EQU     $802D
JF.rdcmd    EQU     $802E
JF.ercmd    EQU     $802F
JF.wrkey    EQU     $C0DE
JF.rdkey    EQU     $DEC0
JF.erkey    EQU     $BEEF

JF.write:   DECLE   JF.wrcmd,   JF.wrkey    ; Copy JLP RAM to flash row  
JF.read:    DECLE   JF.rdcmd,   JF.rdkey    ; Copy flash row to JLP RAM  
JF.erase:   DECLE   JF.ercmd,   JF.erkey    ; Erase flash sector 

;; ======================================================================== ;;
;;  JF.INIT         Copy JLP save-game support routine to System RAM        ;;
;; ======================================================================== ;;
JF.INIT     PROC
            PSHR    R5            
            MVII    #@@__code,  R5
            MVII    #JF.SYSRAM, R4
            REPEAT  5       
            MVI@    R5,         R0      ; \_ Copy code fragment to System RAM
            MVO@    R0,         R4      ; /
            ENDR
            PULR    PC

            ;; === start of code that will run from RAM
@@__code:   MVO@    R0,         R1      ; JF.SYSRAM + 0: initiate command
            ADD@    R1,         PC      ; JF.SYSRAM + 1: Wait for JLP to return
            JR      R5                  ; JF.SYSRAM + 2:
            MVO@    R2,         R2      ; JF.SYSRAM + 3: \__ simple ISR
            JR      R5                  ; JF.SYSRAM + 4: /
            ;; === end of code that will run from RAM
            ENDP

;; ======================================================================== ;;
;;  JF.CMD          Issue a JLP Flash command                               ;;
;;                                                                          ;;
;;  INPUT                                                                   ;;
;;      R0  Slot number to operate on                                       ;;
;;      R1  Address to copy to/from in JLP RAM                              ;;
;;      @R5 Command to invoke:                                              ;;
;;                                                                          ;;
;;              JF.write -- Copy JLP RAM to Flash                           ;;
;;              JF.read  -- Copy Flash to JLP RAM                           ;;
;;              JF.erase -- Erase flash sector                              ;;
;;                                                                          ;;
;;  OUTPUT                                                                  ;;
;;      R0 - R4 not modified.  (Saved and restored across call)             ;;
;;      JLP command executed                                                ;;
;;                                                                          ;;
;;  NOTES                                                                   ;;
;;      This code requires two short routines in the console's System RAM.  ;;
;;      It also requires that the system stack reside in System RAM.        ;;
;;      Because an interrupt may occur during the code's execution, there   ;;
;;      must be sufficient stack space to service the interrupt (8 words).  ;;
;;                                                                          ;;
;;      The code also relies on the fact that the EXEC ISR dispatch does    ;;
;;      not modify R2.  This allows us to initialize R2 for the ISR ahead   ;;
;;      of time, rather than in the ISR.                                    ;;
;; ======================================================================== ;;
JF.CMD      PROC

            MVO     R4,         JF.SV.R4    ; \
            MVII    #JF.SV.R0,  R4          ;  |
            MVO@    R0,         R4          ;  |- Save registers, but not on
            MVO@    R1,         R4          ;  |  the stack.  (limit stack use)
            MVO@    R2,         R4          ; /

            MVI@    R5,         R4          ; Get command to invoke

            MVO     R5,         JF.SV.R5    ; save return address

            DIS
            MVO     R1,         JF.addr     ; \_ Save SG arguments in JLP
            MVO     R0,         JF.row      ; /
                                          
            MVI@    R4,         R1          ; Get command address
            MVI@    R4,         R0          ; Get unlock word
                                          
            MVII    #$100,      R4          ; \
            SDBD                            ;  |_ Save old ISR in save area
            MVI@    R4,         R2          ;  |
            MVO     R2,         JF.SV.ISR   ; /
                                          
            MVII    #JF.SYSRAM + 3, R2      ; \
            MVO     R2,         $100        ;  |_ Set up new ISR in RAM
            SWAP    R2                      ;  |
            MVO     R2,         $101        ; / 
                                          
            MVII    #$20,       R2          ; Address of STIC handshake
            JSRE    R5,  JF.SYSRAM          ; Invoke the command
                                          
            MVI     JF.SV.ISR,  R2          ; \
            MVO     R2,         $100        ;  |_ Restore old ISR 
            SWAP    R2                      ;  |
            MVO     R2,         $101        ; /
                                          
            MVII    #JF.SV.R0,  R5          ; \
            MVI@    R5,         R0          ;  |
            MVI@    R5,         R1          ;  |- Restore registers
            MVI@    R5,         R2          ;  |
            MVI@    R5,         R4          ; /
            MVI@    R5,         PC          ; Return

            ENDP


        ENDI

	IF DEFINED intybasic_fastmult

; Quarter Square Multiplication
; Assembly code by Joe Zbiciak, 2015
; Released to public domain.

QSQR8_TBL:  PROC
            DECLE   $3F80, $3F01, $3E82, $3E04, $3D86, $3D09, $3C8C, $3C10
            DECLE   $3B94, $3B19, $3A9E, $3A24, $39AA, $3931, $38B8, $3840
            DECLE   $37C8, $3751, $36DA, $3664, $35EE, $3579, $3504, $3490
            DECLE   $341C, $33A9, $3336, $32C4, $3252, $31E1, $3170, $3100
            DECLE   $3090, $3021, $2FB2, $2F44, $2ED6, $2E69, $2DFC, $2D90
            DECLE   $2D24, $2CB9, $2C4E, $2BE4, $2B7A, $2B11, $2AA8, $2A40
            DECLE   $29D8, $2971, $290A, $28A4, $283E, $27D9, $2774, $2710
            DECLE   $26AC, $2649, $25E6, $2584, $2522, $24C1, $2460, $2400
            DECLE   $23A0, $2341, $22E2, $2284, $2226, $21C9, $216C, $2110
            DECLE   $20B4, $2059, $1FFE, $1FA4, $1F4A, $1EF1, $1E98, $1E40
            DECLE   $1DE8, $1D91, $1D3A, $1CE4, $1C8E, $1C39, $1BE4, $1B90
            DECLE   $1B3C, $1AE9, $1A96, $1A44, $19F2, $19A1, $1950, $1900
            DECLE   $18B0, $1861, $1812, $17C4, $1776, $1729, $16DC, $1690
            DECLE   $1644, $15F9, $15AE, $1564, $151A, $14D1, $1488, $1440
            DECLE   $13F8, $13B1, $136A, $1324, $12DE, $1299, $1254, $1210
            DECLE   $11CC, $1189, $1146, $1104, $10C2, $1081, $1040, $1000
            DECLE   $0FC0, $0F81, $0F42, $0F04, $0EC6, $0E89, $0E4C, $0E10
            DECLE   $0DD4, $0D99, $0D5E, $0D24, $0CEA, $0CB1, $0C78, $0C40
            DECLE   $0C08, $0BD1, $0B9A, $0B64, $0B2E, $0AF9, $0AC4, $0A90
            DECLE   $0A5C, $0A29, $09F6, $09C4, $0992, $0961, $0930, $0900
            DECLE   $08D0, $08A1, $0872, $0844, $0816, $07E9, $07BC, $0790
            DECLE   $0764, $0739, $070E, $06E4, $06BA, $0691, $0668, $0640
            DECLE   $0618, $05F1, $05CA, $05A4, $057E, $0559, $0534, $0510
            DECLE   $04EC, $04C9, $04A6, $0484, $0462, $0441, $0420, $0400
            DECLE   $03E0, $03C1, $03A2, $0384, $0366, $0349, $032C, $0310
            DECLE   $02F4, $02D9, $02BE, $02A4, $028A, $0271, $0258, $0240
            DECLE   $0228, $0211, $01FA, $01E4, $01CE, $01B9, $01A4, $0190
            DECLE   $017C, $0169, $0156, $0144, $0132, $0121, $0110, $0100
            DECLE   $00F0, $00E1, $00D2, $00C4, $00B6, $00A9, $009C, $0090
            DECLE   $0084, $0079, $006E, $0064, $005A, $0051, $0048, $0040
            DECLE   $0038, $0031, $002A, $0024, $001E, $0019, $0014, $0010
            DECLE   $000C, $0009, $0006, $0004, $0002, $0001, $0000
@@mid:
            DECLE   $0000, $0000, $0001, $0002, $0004, $0006, $0009, $000C
            DECLE   $0010, $0014, $0019, $001E, $0024, $002A, $0031, $0038
            DECLE   $0040, $0048, $0051, $005A, $0064, $006E, $0079, $0084
            DECLE   $0090, $009C, $00A9, $00B6, $00C4, $00D2, $00E1, $00F0
            DECLE   $0100, $0110, $0121, $0132, $0144, $0156, $0169, $017C
            DECLE   $0190, $01A4, $01B9, $01CE, $01E4, $01FA, $0211, $0228
            DECLE   $0240, $0258, $0271, $028A, $02A4, $02BE, $02D9, $02F4
            DECLE   $0310, $032C, $0349, $0366, $0384, $03A2, $03C1, $03E0
            DECLE   $0400, $0420, $0441, $0462, $0484, $04A6, $04C9, $04EC
            DECLE   $0510, $0534, $0559, $057E, $05A4, $05CA, $05F1, $0618
            DECLE   $0640, $0668, $0691, $06BA, $06E4, $070E, $0739, $0764
            DECLE   $0790, $07BC, $07E9, $0816, $0844, $0872, $08A1, $08D0
            DECLE   $0900, $0930, $0961, $0992, $09C4, $09F6, $0A29, $0A5C
            DECLE   $0A90, $0AC4, $0AF9, $0B2E, $0B64, $0B9A, $0BD1, $0C08
            DECLE   $0C40, $0C78, $0CB1, $0CEA, $0D24, $0D5E, $0D99, $0DD4
            DECLE   $0E10, $0E4C, $0E89, $0EC6, $0F04, $0F42, $0F81, $0FC0
            DECLE   $1000, $1040, $1081, $10C2, $1104, $1146, $1189, $11CC
            DECLE   $1210, $1254, $1299, $12DE, $1324, $136A, $13B1, $13F8
            DECLE   $1440, $1488, $14D1, $151A, $1564, $15AE, $15F9, $1644
            DECLE   $1690, $16DC, $1729, $1776, $17C4, $1812, $1861, $18B0
            DECLE   $1900, $1950, $19A1, $19F2, $1A44, $1A96, $1AE9, $1B3C
            DECLE   $1B90, $1BE4, $1C39, $1C8E, $1CE4, $1D3A, $1D91, $1DE8
            DECLE   $1E40, $1E98, $1EF1, $1F4A, $1FA4, $1FFE, $2059, $20B4
            DECLE   $2110, $216C, $21C9, $2226, $2284, $22E2, $2341, $23A0
            DECLE   $2400, $2460, $24C1, $2522, $2584, $25E6, $2649, $26AC
            DECLE   $2710, $2774, $27D9, $283E, $28A4, $290A, $2971, $29D8
            DECLE   $2A40, $2AA8, $2B11, $2B7A, $2BE4, $2C4E, $2CB9, $2D24
            DECLE   $2D90, $2DFC, $2E69, $2ED6, $2F44, $2FB2, $3021, $3090
            DECLE   $3100, $3170, $31E1, $3252, $32C4, $3336, $33A9, $341C
            DECLE   $3490, $3504, $3579, $35EE, $3664, $36DA, $3751, $37C8
            DECLE   $3840, $38B8, $3931, $39AA, $3A24, $3A9E, $3B19, $3B94
            DECLE   $3C10, $3C8C, $3D09, $3D86, $3E04, $3E82, $3F01, $3F80
            DECLE   $4000, $4080, $4101, $4182, $4204, $4286, $4309, $438C
            DECLE   $4410, $4494, $4519, $459E, $4624, $46AA, $4731, $47B8
            DECLE   $4840, $48C8, $4951, $49DA, $4A64, $4AEE, $4B79, $4C04
            DECLE   $4C90, $4D1C, $4DA9, $4E36, $4EC4, $4F52, $4FE1, $5070
            DECLE   $5100, $5190, $5221, $52B2, $5344, $53D6, $5469, $54FC
            DECLE   $5590, $5624, $56B9, $574E, $57E4, $587A, $5911, $59A8
            DECLE   $5A40, $5AD8, $5B71, $5C0A, $5CA4, $5D3E, $5DD9, $5E74
            DECLE   $5F10, $5FAC, $6049, $60E6, $6184, $6222, $62C1, $6360
            DECLE   $6400, $64A0, $6541, $65E2, $6684, $6726, $67C9, $686C
            DECLE   $6910, $69B4, $6A59, $6AFE, $6BA4, $6C4A, $6CF1, $6D98
            DECLE   $6E40, $6EE8, $6F91, $703A, $70E4, $718E, $7239, $72E4
            DECLE   $7390, $743C, $74E9, $7596, $7644, $76F2, $77A1, $7850
            DECLE   $7900, $79B0, $7A61, $7B12, $7BC4, $7C76, $7D29, $7DDC
            DECLE   $7E90, $7F44, $7FF9, $80AE, $8164, $821A, $82D1, $8388
            DECLE   $8440, $84F8, $85B1, $866A, $8724, $87DE, $8899, $8954
            DECLE   $8A10, $8ACC, $8B89, $8C46, $8D04, $8DC2, $8E81, $8F40
            DECLE   $9000, $90C0, $9181, $9242, $9304, $93C6, $9489, $954C
            DECLE   $9610, $96D4, $9799, $985E, $9924, $99EA, $9AB1, $9B78
            DECLE   $9C40, $9D08, $9DD1, $9E9A, $9F64, $A02E, $A0F9, $A1C4
            DECLE   $A290, $A35C, $A429, $A4F6, $A5C4, $A692, $A761, $A830
            DECLE   $A900, $A9D0, $AAA1, $AB72, $AC44, $AD16, $ADE9, $AEBC
            DECLE   $AF90, $B064, $B139, $B20E, $B2E4, $B3BA, $B491, $B568
            DECLE   $B640, $B718, $B7F1, $B8CA, $B9A4, $BA7E, $BB59, $BC34
            DECLE   $BD10, $BDEC, $BEC9, $BFA6, $C084, $C162, $C241, $C320
            DECLE   $C400, $C4E0, $C5C1, $C6A2, $C784, $C866, $C949, $CA2C
            DECLE   $CB10, $CBF4, $CCD9, $CDBE, $CEA4, $CF8A, $D071, $D158
            DECLE   $D240, $D328, $D411, $D4FA, $D5E4, $D6CE, $D7B9, $D8A4
            DECLE   $D990, $DA7C, $DB69, $DC56, $DD44, $DE32, $DF21, $E010
            DECLE   $E100, $E1F0, $E2E1, $E3D2, $E4C4, $E5B6, $E6A9, $E79C
            DECLE   $E890, $E984, $EA79, $EB6E, $EC64, $ED5A, $EE51, $EF48
            DECLE   $F040, $F138, $F231, $F32A, $F424, $F51E, $F619, $F714
            DECLE   $F810, $F90C, $FA09, $FB06, $FC04, $FD02, $FE01
            ENDP

; R0 = R0 * R1, where R0 and R1 are unsigned 8-bit values
; Destroys R1, R4
qs_mpy8:    PROC
            MOVR    R0,             R4      ;   6
            ADDI    #QSQR8_TBL.mid, R1      ;   8
            ADDR    R1,             R4      ;   6   a + b
            SUBR    R0,             R1      ;   6   a - b
@@ok:       MVI@    R4,             R0      ;   8
            SUB@    R1,             R0      ;   8
            JR      R5                      ;   7
                                            ;----
                                            ;  49
            ENDP
            

; R1 = R0 * R1, where R0 and R1 are 16-bit values
; destroys R0, R2, R3, R4, R5
qs_mpy16:   PROC
            PSHR    R5                  ;   9
                                   
            ; Unpack lo/hi
            MOVR    R0,         R2      ;   6   
            ANDI    #$FF,       R0      ;   8   R0 is lo(a)
            XORR    R0,         R2      ;   6   
            SWAP    R2                  ;   6   R2 is hi(a)

            MOVR    R1,         R3      ;   6   R3 is orig 16-bit b
            ANDI    #$FF,       R1      ;   8   R1 is lo(b)
            MOVR    R1,         R5      ;   6   R5 is lo(b)
            XORR    R1,         R3      ;   6   
            SWAP    R3                  ;   6   R3 is hi(b)
                                        ;----
                                        ;  67
                                        
            ; lo * lo                   
            MOVR    R0,         R4      ;   6   R4 is lo(a)
            ADDI    #QSQR8_TBL.mid, R1  ;   8
            ADDR    R1,         R4      ;   6   R4 = lo(a) + lo(b)
            SUBR    R0,         R1      ;   6   R1 = lo(a) - lo(b)
                                        
@@pos_ll:   MVI@    R4,         R4      ;   8   R4 = qstbl[lo(a)+lo(b)]
            SUB@    R1,         R4      ;   8   R4 = lo(a)*lo(b)
                                        ;----
                                        ;  42
                                        ;  67 (carried forward)
                                        ;----
                                        ; 109
                                       
            ; lo * hi                  
            MOVR    R0,         R1      ;   6   R0 = R1 = lo(a)
            ADDI    #QSQR8_TBL.mid, R3  ;   8
            ADDR    R3,         R1      ;   6   R1 = hi(b) + lo(a)
            SUBR    R0,         R3      ;   6   R3 = hi(b) - lo(a)
                                       
@@pos_lh:   MVI@    R1,         R1      ;   8   R1 = qstbl[hi(b)-lo(a)]
            SUB@    R3,         R1      ;   8   R1 = lo(a)*hi(b)
                                        ;----
                                        ;  42
                                        ; 109 (carried forward)
                                        ;----
                                        ; 151
                                       
            ; hi * lo                  
            MOVR    R5,         R0      ;   6   R5 = R0 = lo(b)
            ADDI    #QSQR8_TBL.mid, R2  ;   8
            ADDR    R2,         R5      ;   6   R3 = hi(a) + lo(b)
            SUBR    R0,         R2      ;   6   R2 = hi(a) - lo(b)
                                       
@@pos_hl:   ADD@    R5,         R1      ;   8   \_ R1 = lo(a)*hi(b)+hi(a)*lo(b)
            SUB@    R2,         R1      ;   8   /
                                        ;----
                                        ;  42
                                        ; 151 (carried forward)
                                        ;----
                                        ; 193
                                       
            SWAP    R1                  ;   6   \_ shift upper product left 8
            ANDI    #$FF00,     R1      ;   8   /
            ADDR    R4,         R1      ;   6   final product
            PULR    PC                  ;  12
                                        ;----
                                        ;  32
                                        ; 193 (carried forward)
                                        ;----
                                        ; 225
            ENDP

	ENDI

	IF DEFINED intybasic_fastdiv

; Fast unsigned division/remainder
; Assembly code by Oscar Toledo G. Jul/10/2015
; Released to public domain.

	; Ultrafast unsigned division/remainder operation
	; Entry: R0 = Dividend
	;        R1 = Divisor
	; Output: R0 = Quotient
	;         R2 = Remainder
	; Worst case: 6 + 6 + 9 + 496 = 517 cycles
	; Best case: 6 + (6 + 7) * 16 = 214 cycles

uf_udiv16:	PROC
	CLRR R2		; 6
	SLLC R0,1	; 6
	BC @@1		; 7/9
	SLLC R0,1	; 6
	BC @@2		; 7/9
	SLLC R0,1	; 6
	BC @@3		; 7/9
	SLLC R0,1	; 6
	BC @@4		; 7/9
	SLLC R0,1	; 6
	BC @@5		; 7/9
	SLLC R0,1	; 6
	BC @@6		; 7/9
	SLLC R0,1	; 6
	BC @@7		; 7/9
	SLLC R0,1	; 6
	BC @@8		; 7/9
	SLLC R0,1	; 6
	BC @@9		; 7/9
	SLLC R0,1	; 6
	BC @@10		; 7/9
	SLLC R0,1	; 6
	BC @@11		; 7/9
	SLLC R0,1	; 6
	BC @@12		; 7/9
	SLLC R0,1	; 6
	BC @@13		; 7/9
	SLLC R0,1	; 6
	BC @@14		; 7/9
	SLLC R0,1	; 6
	BC @@15		; 7/9
	SLLC R0,1	; 6
	BC @@16		; 7/9
	JR R5

@@1:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@2:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@3:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@4:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@5:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@6:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@7:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@8:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@9:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@10:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@11:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@12:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@13:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@14:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@15:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
@@16:	RLC R2,1	; 6
	CMPR R1,R2	; 6
	BNC $+3		; 7/9
	SUBR R1,R2	; 6
	RLC R0,1	; 6
	JR R5
	
	ENDP

	ENDI

	IF DEFINED intybasic_ecs
	ORG $4800	; Available up to $4FFF

        ; Disable ECS ROMs so that they don't conflict with us
        MVII    #$2A5F, R0
        MVO     R0,     $2FFF
        MVII    #$7A5F, R0
        MVO     R0,     $7FFF
        MVII    #$EA5F, R0
        MVO     R0,     $EFFF

        B       $1041       ; resume boot

	ENDI

        ORG $200,$200,"-RWB"

Q2:	; Reserved label for #BACKTAB

	ORG $319,$319,"-RWB"
        ;
        ; 16-bits variables
	; Note IntyBASIC variables grow up starting in $308.
        ;
        IF DEFINED intybasic_voice
IV.Q:      RMB 8    ; IV_xxx        16-bit          Voice queue  (8 words)
IV.FPTR:   RMB 1    ; IV_xxx        16-bit          Current FIFO ptr.
IV.PPTR:   RMB 1    ; IV_xxx        16-bit          Current Phrase ptr.
        ENDI

        ORG $323,$323,"-RWB"

_scroll_buffer: RMB 20  ; Sometimes this is unused
_music_table:	RMB 1	; Note table
_music_start:	RMB 1	; Start of music
_music_p:	RMB 1	; Pointer to music
_frame:         RMB 1   ; Current frame
_read:          RMB 1   ; Pointer to DATA
_gram_bitmap:   RMB 1   ; Bitmap for definition
_gram2_bitmap:  RMB 1   ; Secondary bitmap for definition
_screen:    RMB 1       ; Pointer to current screen position
_color:     RMB 1       ; Current color

Q1:			; Reserved label for #MOBSHADOW
_mobs:      RMB 3*8     ; MOB buffer

_col0:      RMB 1       ; Collision status for MOB0
_col1:      RMB 1       ; Collision status for MOB1
_col2:      RMB 1       ; Collision status for MOB2
_col3:      RMB 1       ; Collision status for MOB3
_col4:      RMB 1       ; Collision status for MOB4
_col5:      RMB 1       ; Collision status for MOB5
_col6:      RMB 1       ; Collision status for MOB6
_col7:      RMB 1       ; Collision status for MOB7

SCRATCH:    ORG $100,$100,"-RWBN"
        ;
        ; 8-bits variables
        ;
ISRVEC:     RMB 2       ; Pointer to ISR vector (required by Intellivision ROM)
_int:       RMB 1       ; Signals interrupt received
_ntsc:      RMB 1       ; Signals NTSC Intellivision
_rand:      RMB 1       ; Pseudo-random value
_gram_target:   RMB 1   ; Contains GRAM card number
_gram_total:    RMB 1   ; Contains total GRAM cards for definition
_gram2_target:  RMB 1   ; Contains GRAM card number
_gram2_total:   RMB 1   ; Contains total GRAM cards for definition
_mode_select:   RMB 1   ; Graphics mode selection
_border_color:  RMB 1   ; Border color
_border_mask:   RMB 1   ; Border mask
    IF DEFINED intybasic_keypad
_cnt1_p0:   RMB 1       ; Debouncing 1
_cnt1_p1:   RMB 1       ; Debouncing 2
_cnt1_key:  RMB 1       ; Currently pressed key
_cnt2_p0:   RMB 1       ; Debouncing 1
_cnt2_p1:   RMB 1       ; Debouncing 2
_cnt2_key:  RMB 1       ; Currently pressed key
    ENDI
    IF DEFINED intybasic_scroll
_scroll_x:  RMB 1       ; Scroll X offset
_scroll_y:  RMB 1       ; Scroll Y offset
_scroll_d:  RMB 1       ; Scroll direction
    ENDI
    IF DEFINED intybasic_music
_music_mode: RMB 1      ; Music mode (0= Not using PSG, 2= Simple, 4= Full, add 1 if using noise channel for drums)
_music_frame: RMB 1     ; Music frame (for 50 hz fixed)
_music_tc:  RMB 1       ; Time counter
_music_t:   RMB 1       ; Time base
_music_i1:  RMB 1       ; Instrument 1 
_music_s1:  RMB 1       ; Sample pointer 1
_music_n1:  RMB 1       ; Note 1
_music_i2:  RMB 1       ; Instrument 2
_music_s2:  RMB 1       ; Sample pointer 2
_music_n2:  RMB 1       ; Note 2
_music_i3:  RMB 1       ; Instrument 3
_music_s3:  RMB 1       ; Sample pointer 3
_music_n3:  RMB 1       ; Note 3
_music_s4:  RMB 1       ; Sample pointer 4
_music_n4:  RMB 1       ; Note 4 (really it's drum)

_music_freq10:	RMB 1   ; Low byte frequency A
_music_freq20:	RMB 1   ; Low byte frequency B
_music_freq30:	RMB 1   ; Low byte frequency C
_music_freq11:	RMB 1   ; High byte frequency A
_music_freq21:	RMB 1   ; High byte frequency B
_music_freq31:	RMB 1   ; High byte frequency C
_music_mix:	RMB 1   ; Mixer
_music_noise:	RMB 1   ; Noise
_music_vol1:	RMB 1   ; Volume A
_music_vol2:	RMB 1   ; Volume B
_music_vol3:	RMB 1   ; Volume C
    ENDI
    IF DEFINED intybasic_music_volume
_music_vol:	RMB 1	; Global music volume
    ENDI
    IF DEFINED intybasic_voice
IV.QH:     RMB 1    ; IV_xxx        8-bit           Voice queue head
IV.QT:     RMB 1    ; IV_xxx        8-bit           Voice queue tail
IV.FLEN:   RMB 1    ; IV_xxx        8-bit           Length of FIFO data
    ENDI


V1:	RMB 1	; A
V8:	RMB 1	; BONUS_EXP
V9:	RMB 1	; BONUS_LIVES
V10:	RMB 1	; CHANCE
V11:	RMB 1	; DIFICULTY
V16:	RMB 1	; HEARTRATE
V7:	RMB 1	; INVISIBLE
V14:	RMB 1	; JUMP
V18:	RMB 1	; LEVEL
V17:	RMB 1	; LIVES
V22:	RMB 1	; PAUSED
V4:	RMB 1	; PLAYERDX
V6:	RMB 1	; PLAYERF
V2:	RMB 1	; PLAYERX
V5:	RMB 1	; PLAYERY
V21:	RMB 1	; POWER
V13:	RMB 1	; SCENE
V20:	RMB 1	; STREET_LINEY
V19:	RMB 1	; UNIVCLOCK
Q5:	RMB 3	; OBJECT
Q3:	RMB 3	; OBJECTX
Q4:	RMB 3	; OBJECTY
Q7:	RMB 4	; PERCENTAGE
_SCRATCH:	EQU $

SYSTEM:	ORG $2F0, $2F0, "-RWBN"
STACK:	RMB 24
V12:	RMB 1	; #MAXIMUNSCORE
V3:	RMB 1	; #PLAYERCOLOR
V15:	RMB 1	; #SCORE
Q6:	RMB 4	; #OBJECTCOLOR
_SYSTEM:	EQU $
