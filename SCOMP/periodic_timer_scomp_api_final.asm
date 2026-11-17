; ECE 2031 - Periodic Oscillating Timer
; SCOMP timer API / standalone debug program (Keshav)
;
; Matches vhdl/peripheral.vhd and oscillating_timer_game.asm on
; GitHub main as inspected 2026-11-17.
;
; Public routines:
;   InitTimer       - write initial settings and restart running timer
;   SetInterval     - write INTERVAL (takes effect on next restart)
;   SetSpeed        - write SPEED (takes effect immediately)
;   SetMax          - write MAX (takes effect immediately; 0=unlimited)
;   PauseTimer      - pause without changing timer position
;   ResumeTimer     - resume from current position
;   ReverseTimer    - reverse once (only in the interior of the interval)
;   ResetTimer      - restart at 0 or INTERVAL, clear count/event
;   ClearTimerEvent - acknowledge/clear the VHDL event_pending flag
;   EnableTimerIRQ  - enable IRQ output from the peripheral
;   DisableTimerIRQ - disable IRQ output from the peripheral
;   IncreaseSpeed   - increase speed by 1, up to MaxSpeed
;   DecreaseSpeed   - decrease speed by SpeedDrop, down to MinSpeed
;   ReadTimer       - cache PT_TIMER in CurrentTimer
;   ReadCount       - cache PT_COUNT in CompletedIntervals
;   PollTimerEvent  - detect COUNT changes, store 0/1 in EventOccurred
;
; NOTE: The existing VHDL has NO PT_STATUS register. PollTimerEvent
; detects changes in COUNT; it does not read the internal IRQ flag.
;
; CONTROL is a bitfield (not numbered commands):
;   bit 0 =  1  restart       one-shot; also loads INTERVAL
;   bit 1 =  2  start upward  sampled only together with restart
;   bit 2 =  4  pause         persistent setting; 1=paused, 0=running
;   bit 3 =  8  IRQ enable    persistent setting; 1=enabled, 0=disabled
;   bit 4 = 16  acknowledge   one-shot; clears pending event
;   bit 5 = 32  reverse       one-shot; only between endpoints
;
; IMPORTANT: Every OUT PT_CONTROL overwrites bits 2 and 3.
; PauseMask and IRQMask track those bits so sending a command does
; not accidentally unpause the timer or disable IRQ.
;
; All routines may change the accumulator (AC).
; This file runs as a standalone debug program. To use these routines
; inside the game, merge the routines/data into ONE assembly program;
; keep only one ORG 0, one Start label, and one definition per symbol.

ORG 0

; STANDALONE TEST HARNESS (not part of the reusable routines)
Start:
    CALL InitTimer

DebugLoop:
    CALL ReadTimer
    LOAD CurrentTimer
    OUT HEX0

    CALL ReadCount
    LOAD CompletedIntervals
    OUT HEX1

    CALL PollTimerEvent
    LOAD EventOccurred
    JZERO DebugLoop
    CALL ClearTimerEvent
    JUMP DebugLoop

; INITIALIZATION
InitTimer:
    LOADI 0
    STORE PauseMask
    STORE IRQMask
    STORE LastObservedCount
    STORE EventOccurred
    STORE CompletedIntervals

    LOAD ConfigInterval
    OUT PT_INTERVAL
    LOAD ConfigSpeed
    OUT PT_SPEED
    LOAD ConfigMax
    OUT PT_MAX

    ; A restart loads INTERVAL and selects initial direction.
    LOAD StartDirection
    JZERO InitDown
InitUp:
    LOADI CMD_START_UP
    OUT PT_CONTROL
    RETURN
InitDown:
    LOADI CMD_START_DOWN
    OUT PT_CONTROL
    RETURN

; CONFIGURATION
SetInterval:
    LOAD ConfigInterval
    OUT PT_INTERVAL
    RETURN

SetSpeed:
    LOAD ConfigSpeed
    OUT PT_SPEED
    RETURN

SetMax:
    LOAD ConfigMax
    OUT PT_MAX
    RETURN

; PERSISTENT CONTROL SETTINGS
PauseTimer:
    LOADI CTRL_PAUSE
    STORE PauseMask
    ADD IRQMask
    OUT PT_CONTROL
    RETURN

ResumeTimer:
    LOADI 0
    STORE PauseMask
    ADD IRQMask
    OUT PT_CONTROL
    RETURN

EnableTimerIRQ:
    LOADI CTRL_IRQ
    STORE IRQMask
    ADD PauseMask
    OUT PT_CONTROL
    RETURN

DisableTimerIRQ:
    LOADI 0
    STORE IRQMask
    ADD PauseMask
    OUT PT_CONTROL
    RETURN

; ONE-SHOT CONTROL COMMANDS
ReverseTimer:
    LOAD PauseMask
    ADD IRQMask
    ADDI CTRL_REVERSE
    OUT PT_CONTROL
    RETURN

ClearTimerEvent:
    LOAD PauseMask
    ADD IRQMask
    ADDI CTRL_ACK
    OUT PT_CONTROL
    RETURN

ResetTimer:
    ; Restart clears position/count/pending in the VHDL.
    ; It also loads the last value written to PT_INTERVAL.
    LOADI 0
    STORE LastObservedCount
    STORE CompletedIntervals
    STORE EventOccurred

    LOAD StartDirection
    JZERO ResetDown
ResetUp:
    LOAD PauseMask
    ADD IRQMask
    ADDI CMD_START_UP
    OUT PT_CONTROL
    RETURN
ResetDown:
    LOAD PauseMask
    ADD IRQMask
    ADDI CMD_START_DOWN
    OUT PT_CONTROL
    RETURN

; SPEED HELPERS: same speed bounds and flip decrement as the game.
IncreaseSpeed:
    LOAD ConfigSpeed
    SUB MaxSpeed
    JNEG DoIncrease
    RETURN
DoIncrease:
    LOAD ConfigSpeed
    ADDI 1
    STORE ConfigSpeed
    OUT PT_SPEED
    RETURN

DecreaseSpeed:
    LOAD ConfigSpeed
    SUB SpeedDrop
    SUB MinSpeed
    JNEG ClampSpeed
    LOAD ConfigSpeed
    SUB SpeedDrop
    STORE ConfigSpeed
    OUT PT_SPEED
    RETURN
ClampSpeed:
    LOAD MinSpeed
    STORE ConfigSpeed
    OUT PT_SPEED
    RETURN

; READBACK
ReadTimer:
    IN PT_TIMER
    STORE CurrentTimer
    RETURN

ReadCount:
    IN PT_COUNT
    STORE CompletedIntervals
    RETURN

; SOFTWARE EVENT DETECTION
; The actual event_pending flag is NOT readable in current VHDL.
; Report one event if COUNT differs from the previous observation.
; Multiple endpoint arrivals between polls are coalesced into one.
; ResetTimer and InitTimer reset the baseline to COUNT=0.
PollTimerEvent:
    IN PT_COUNT
    STORE CompletedIntervals
    SUB LastObservedCount
    JZERO NoNewEvent

    LOAD CompletedIntervals
    STORE LastObservedCount
    LOADI 1
    STORE EventOccurred
    RETURN
NoNewEvent:
    LOADI 0
    STORE EventOccurred
    RETURN

; CONFIGURATION / SOFTWARE STATE
; Defaults match oscillating_timer_game.asm
ConfigInterval:     DW 100   ; timer oscillates between 0 and 100
ConfigSpeed:        DW 40    ; base 10 Hz * 40 = 400 steps/sec
ConfigMax:          DW 0     ; zero means no endpoint limit
StartDirection:     DW 1     ; 1=up from 0, 0=down from INTERVAL
MinSpeed:           DW 1
MaxSpeed:           DW 60
SpeedDrop:          DW 4

PauseMask:          DW 0     ; always 0 or 4
IRQMask:            DW 0     ; always 0 or 8
CurrentTimer:       DW 0
CompletedIntervals: DW 0
LastObservedCount:  DW 0
EventOccurred:      DW 0

; REGISTER ADDRESSES: match BASE_ADDR = 0x20 in VHDL
HEX0:        EQU 4
HEX1:        EQU 5
PT_INTERVAL: EQU 32    ; 0x20, write-only
PT_SPEED:    EQU 33    ; 0x21, write-only
PT_MAX:      EQU 34    ; 0x22, write-only
PT_CONTROL:  EQU 35    ; 0x23, write-only
PT_TIMER:    EQU 36    ; 0x24, read-only
PT_COUNT:    EQU 37    ; 0x25, read-only

; CONTROL BIT MASKS
CTRL_RESTART: EQU 1
CTRL_UP:      EQU 2
CTRL_PAUSE:   EQU 4
CTRL_IRQ:     EQU 8
CTRL_ACK:     EQU 16
CTRL_REVERSE: EQU 32

; Useful combinations. These start the timer on restart.
CMD_START_UP:   EQU 3     ; restart + count upward
CMD_START_DOWN: EQU 1     ; restart + count downward
