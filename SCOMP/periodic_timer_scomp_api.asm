; ECE 2031 - Periodic Oscillating Timer
; SCOMP peripheral-control module (Keshav)
;
; draft API: address/command values are placeholders
; the GitHub VHDL is not yet connected to SCOMP's I/O bus
;
; Public interface for the game portion:
;   InitTimer, PauseTimer, ResumeTimer, ReverseTimer, ResetTimer,
;   SetSpeed, DecreaseSpeed, ReadTimer, ReadCount,
;   ReadStatus, PollTimerEvent, ClearTimerEvent
;
; Config: ConfigInterval, ConfigSpeed, ConfigMax, StartDirection
; Results: CurrentTimer, CompletedIntervals, EventOccurred
; Subroutines may modify the accumulator (AC).

ORG 0

; TEST HARNESS ONLY: replace with Adwaith's game entry point
Start:
    CALL InitTimer

DebugLoop:
    CALL ReadTimer
    LOAD CurrentTimer
    OUT Hex0

    CALL ReadCount
    LOAD CompletedIntervals
    OUT Hex1

    CALL PollTimerEvent
    LOAD EventOccurred
    JZERO DebugLoop

    CALL ClearTimerEvent
    JUMP DebugLoop

; CONFIGURE / START
InitTimer:
    LOAD ConfigInterval
    OUT PT_INTERVAL

    LOAD ConfigSpeed
    OUT PT_SPEED

    LOAD ConfigMax
    OUT PT_MAX

    ; TODO: START command must cause a VHDL load_config pulse.
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

; RUNTIME CONTROLS
PauseTimer:
    LOADI CMD_PAUSE
    OUT PT_CONTROL
    RETURN

ResumeTimer:
    LOADI CMD_RESUME
    OUT PT_CONTROL
    RETURN

ReverseTimer:
    ; TODO: VHDL needs mid-interval reverse without resetting position.
    LOADI CMD_REVERSE
    OUT PT_CONTROL
    RETURN

ResetTimer:
    ; TODO: Decide what RESET clears (position/count/status).
    LOADI CMD_RESET
    OUT PT_CONTROL
    RETURN

ClearTimerEvent:
    ; TODO: Map command to VHDL clear_pending pulse.
    LOADI CMD_ACK_EVENT
    OUT PT_CONTROL
    RETURN

; SPEED CONTROL
; Provisional convention: larger SPEED number means faster ticks.
SetSpeed:
    LOAD ConfigSpeed
    OUT PT_SPEED
    RETURN

DecreaseSpeed:
    LOAD ConfigSpeed
    SUB MinSpeed
    JPOS LowerSpeed
    RETURN

LowerSpeed:
    LOAD ConfigSpeed
    ADDI -1
    STORE ConfigSpeed
    CALL SetSpeed
    RETURN

; READ PERIPHERAL VALUES
ReadTimer:
    IN PT_TIMER
    STORE CurrentTimer
    RETURN

ReadCount:
    IN PT_COUNT
    STORE CompletedIntervals
    RETURN

ReadStatus:
    ; TODO: Implement memory-mapped STATUS register in VHDL.
    IN PT_STATUS
    STORE CurrentStatus
    RETURN

PollTimerEvent:
    ; Non-blocking. STATUS bit 0 is assumed to mean event_pending.
    CALL ReadStatus
    LOAD CurrentStatus
    AND EventBitMask
    JZERO NoEvent

    LOADI 1
    STORE EventOccurred
    RETURN

NoEvent:
    LOADI 0
    STORE EventOccurred
    RETURN

; SHARED CONFIGURATION / RESULTS
ConfigInterval:      DW 100 ; TODO: define interval units / semantics
ConfigSpeed:         DW 5   ; TODO: define frequency mapping
ConfigMax:           DW 100 ; TODO: define relationship to INTERVAL
StartDirection:      DW 1   ; proposed 1=up, 0=down
MinSpeed:            DW 1
CurrentTimer:        DW 0
CompletedIntervals:  DW 0
CurrentStatus:       DW 0
EventOccurred:       DW 0
EventBitMask:        DW 1   ; provisional STATUS bit 0

; PROVISIONAL I/O ADDRESSES - TODO: REPLACE
Hex0:           EQU 4
Hex1:           EQU 5
PT_INTERVAL:    EQU 16
PT_SPEED:       EQU 17
PT_MAX:         EQU 18
PT_CONTROL:     EQU 19
PT_TIMER:       EQU 20
PT_COUNT:       EQU 21
PT_STATUS:      EQU 22

; PROVISIONAL CONTROL COMMAND VALUES - TODO: REPLACE
; Assumes command-based writes, not a persistent bitfield.
CMD_START_UP:   EQU 1
CMD_START_DOWN: EQU 2
CMD_PAUSE:      EQU 3
CMD_RESUME:     EQU 4
CMD_REVERSE:    EQU 5
CMD_RESET:      EQU 6
CMD_ACK_EVENT:  EQU 7
