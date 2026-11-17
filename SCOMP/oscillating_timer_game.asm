; ECE 2031 - Periodic Oscillating Timer
; SCOMP game program  (Adwaith)
;
; Rules: 
;   - The peripheral timer oscillates between 0 and INTERVAL
;   - The clock speeds up every time an interval completes, COUNT increments, and slows down every time the player flips the switch
;   - The player flips SW0 to reverse
;
; Display: 
;   LEDS -> current timer position (visual bar)
;   HEX0 -> score (number of flips)
;   HEX1 -> valid reversals

ORG 0
Start:
    CALL InitGame

MainLoop:
    ; Samples peripheral
    IN PT_TIMER
    STORE CurTimer
    IN PT_COUNT
    STORE CurCount

    ; Display
    LOAD CurTimer
    OUT LEDS
    LOAD Score
    OUT HEX0
    LOAD ValidHits
    OUT HEX1

    ; Win or not (check)
    LOAD ValidHits
    SUB CFG_TARGET
    JNEG NotWon
    JUMP Win

NotWon:
    ; Increases speed
    LOAD CurCount
    SUB PrevCount
    JZERO ReadSwitch
    CALL IncreaseSpeed
    LOAD CurCount
    STORE PrevCount

ReadSwitch:
    IN SW
    AND SWITCH_MASK
    STORE CurSwitch

    LOAD CurSwitch
    JZERO StorePrev
    LOAD PrevSwitch
    JPOS StorePrev
    CALL OnFlip

StorePrev:
    LOAD CurSwitch
    STORE PrevSwitch
    JUMP MainLoop

Win:
    LOAD LEDS_ALL
    OUT LEDS
    LOAD Score
    OUT HEX0
    LOAD ValidHits
    OUT HEX1
    JUMP Win

InitGame:
    LOADI 0
    STORE Score
    STORE ValidHits
    STORE PrevSwitch
    STORE CurSwitch
    STORE PrevCount
    STORE CurCount
    STORE CurTimer

    LOAD CFG_SPEED
    STORE Speed

    LOAD CFG_INTERVAL
    OUT PT_INTERVAL
    LOAD CFG_MAX
    OUT PT_MAX
    LOAD Speed
    OUT PT_SPEED

    LOADI CMD_START_UP
    OUT PT_CONTROL
    RETURN

OnFlip:
    LOAD Score
    ADDI 1
    STORE Score

    ; Reverses
    IN PT_TIMER
    STORE CurTimer
    LOADI CMD_REVERSE
    OUT PT_CONTROL

    ; Slows clock down
    LOAD Speed
    SUB SPEED_STEP
    STORE Speed
    SUB SPEED_FLOOR
    JNEG FlipSpeedUnder
    LOAD Speed
    OUT PT_SPEED
    JUMP FlipValidity
FlipSpeedUnder:
    LOAD SPEED_FLOOR
    STORE Speed
    OUT PT_SPEED

    ; Checks if reversal is valid
FlipValidity:
    LOAD CurTimer
    JZERO FlipDelay
    SUB CFG_INTERVAL
    JZERO FlipDelay
    JNEG FlipHit
    JUMP FlipDelay
FlipHit:
    LOAD ValidHits
    ADDI 1
    STORE ValidHits

FlipDelay:
    LOADI 100
    STORE DelayCnt
FlipDelayOuter:
    LOADI 100
FlipDelayInner:
    ADDI -1
    JZERO FlipDelayNext
    JUMP FlipDelayInner
FlipDelayNext:
    LOAD DelayCnt
    ADDI -1
    STORE DelayCnt
    JZERO FlipDone
    JUMP FlipDelayOuter
FlipDone:
    RETURN

IncreaseSpeed:
    LOAD Speed
    ADDI 1
    STORE Speed
    SUB SPEED_CEIL
    JPOS SpeedOver
    LOAD Speed
    OUT PT_SPEED
    RETURN
SpeedOver:
    LOAD SPEED_CEIL
    STORE Speed
    OUT PT_SPEED
    RETURN


; Game params
CFG_INTERVAL:  DW 100    ; oscillation upper endpoint (0..INTERVAL)
CFG_SPEED:     DW 40     ; starting speed multiplier
CFG_MAX:       DW 0      ; 0 = never freeze
CFG_TARGET:    DW 3      ; valid in-interval reversals needed to win
SPEED_STEP:    DW 4      ; speed drop per flip
SPEED_FLOOR:   DW 1      ; minimum speed
SPEED_CEIL:    DW 60     ; maximum speed
SWITCH_MASK:   DW 1      ; SW0
LEDS_ALL:      DW 1023   ; all 10 LEDs on

CurTimer:   DW 0
CurCount:   DW 0
PrevCount:  DW 0
Score:      DW 0
ValidHits:  DW 0
CurSwitch:  DW 0
PrevSwitch: DW 0
Speed:      DW 0
DelayCnt:   DW 0

SW:    EQU 0
LEDS:  EQU 1
HEX0:  EQU 4
HEX1:  EQU 5

PT_INTERVAL: EQU 32      ; 0x20
PT_SPEED:    EQU 33      ; 0x21
PT_MAX:      EQU 34      ; 0x22
PT_CONTROL:  EQU 35      ; 0x23
PT_TIMER:    EQU 36      ; 0x24
PT_COUNT:    EQU 37      ; 0x25

CMD_START_UP:   EQU 3    ; RST|UP  (0x03)
CMD_START_DOWN: EQU 1    ; RST     (0x01)
CMD_PAUSE:      EQU 4    ; P       (0x04)
CMD_RESUME:     EQU 0    ;         (0x00)
CMD_REVERSE:    EQU 32   ; REV     (0x20)
CMD_ACK:        EQU 16   ; ACK     (0x10)
CMD_IRQ_ON:     EQU 8    ; IRQ     (0x08)
