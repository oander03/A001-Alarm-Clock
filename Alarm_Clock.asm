; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.7 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'CLEAR' push button connected to P1.5 is pressed.
$NOLIST
$MODN76E003
$LIST



; Snooze button
; Volume button 
; am pm at 11:59:59 switch
; edit button
; switch blink animations
; watch 
; timer
; timer doesnt have am-pm
; has less buttons

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK           EQU 16600000 ; Microcontroller system frequency in Hz
TIMER0_RATE   EQU 1024    ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

TONE_1024 EQU ((65536-(CLK/1024)))
TONE_4096 EQU ((65536-(CLK/4096)))

DOWN_BUTTON   equ P1.6
UP_BUTTON     equ P1.7
EDIT_BUTTON	  equ P3.0
CHANGE_BUTTON equ P0.5
ONOFF_BUTTON  equ P1.5
SOUND_OUT     equ P1.2

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
seconds_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
minutes_counter:  ds 1
hours_counter:  ds 1
seconds_counter_2:  ds 1 
minutes_counter_2:  ds 1
hours_counter_2:  ds 1
Timer0Reload:   ds 2     ; 16-bit reload value (low, high)
edit_counter:  ds 1
edit_counter_2:  ds 1

Top_Change_counter:  ds 1
Bottom_Change_counter: ds 1


; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
second_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
vol_controls: dbit 1
am_pm: dbit 1
am_pm_2: dbit 1
change_flag: dbit 1
onoff_flag: dbit 1
watch_flag: dbit 1
timer_flag: dbit 1

am_pm_clamp: dbit 1

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter
Clock_Message:  db 'Clock:01:00:00', 0
Clock_Message_2:  db 'Clock', 0
Alarm_Message:  db 'Alarm:01:00:00', 0
Alarm_Message_2:  db 'Alarm', 0
Timer_Message:  db 'Timer:xx:xx:xx  ', 0
Watch_Message:  db 'Watch:xx:xx:xx  ', 0
Lap_Message:  db 'Lap:xx:xx:xx', 0
Blank_Message:  db '  ', 0
Blank_Message_2:  db '     ', 0
Clear_Message:  db '                ', 0
Set_Message:  db 'set:xx:xx:xx', 0


;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	orl CKCON, #0b00001000 ; Input for timer 0 is sysclk/1
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, Timer0Reload+1
	mov TL0, Timer0Reload+0
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz wave at pin SOUND_OUT   ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	; Timer 0 doesn't have 16-bit auto-reload, so
	clr TR0
	mov TH0, Timer0Reload+1
	mov TL0, Timer0Reload+0
	setb TR0
	cpl SOUND_OUT ; Connect speaker the pin assigned to 'SOUND_OUT'!
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	orl T2MOD, #0x80 ; Enable timer 2 autoreload
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR.  It is bit addressable.
	cpl P0.4 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1 second have passed.  Set a flag so the main program knows
	setb second_flag ; Let the main program know half second had passed
	;cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, seconds_counter
	

	
	;jnb UPDOWN, Timer2_ISR_decrement
	add a, #0x01
	sjmp Timer2_ISR_da
	
	
Timer2_ISR_decrement:
	add a, #0x99 ; Adding the 10-complement of -1 is like subtracting 1.

Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov seconds_counter, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti
	


;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    mov P0M1, #0x00
    mov P0M2, #0x00
    mov P1M1, #0x00
    mov P1M2, #0x00
    mov P3M1, #0x00
    mov P3M2, #0x00
          
    lcall Timer0_Init
    lcall Timer2_Init
    setb EA   ; Enable Global interrupts
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    
    clr  ET0          ; disable Timer0 interrupt
    clr  TR0
    cpl TR2
    
    ;Check mark custom character #0
	WriteCommand(#0x40)
	
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00001B)
	WriteData(#00010B)
	WriteData(#10100B)
	WriteData(#01000B)
	WriteData(#00000B)
	WriteData(#00000B)
	
	;X custom character #1
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#01010B)
	WriteData(#00100B)
	WriteData(#01010B)
	WriteData(#00000B)
	WriteData(#00000B)
	
	;low vol custom character #2
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#00000B)
	
	;high vol custom character #3
	WriteData(#00000B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#01110B)
	WriteData(#00000B)
	
	;arrow custom character #4
	WriteData(#00000B)
	WriteData(#00000B)
	WriteData(#00100B)
	WriteData(#01000B)
	WriteData(#11111B)
	WriteData(#01000B)
	WriteData(#00100B)
	WriteData(#00000B)
	
	;full custom character #5
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	WriteData(#11111B)
	
	
	Set_Cursor(1, 1)
    mov a, #01h

animation_loop_start:
    cjne a, #22h, animation_loop
    sjmp animation_loop_done

animation_loop:

	cjne a, #11h, animation_loop_continue
		Set_Cursor(2, 1)
	
	animation_loop_continue:
    Display_char(#5)
    Wait_Milli_Seconds(#25)

    inc a
    sjmp animation_loop_start

animation_loop_done:


	
	clr a 
	
	Set_Cursor(1, 1)
    Send_Constant_String(#Clear_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#Clear_Message)
    
	Set_Cursor(1, 1)
    Send_Constant_String(#Clock_Message)
    Set_Cursor(2, 1)
    Send_Constant_String(#Alarm_Message)
    setb second_flag
    
	mov seconds_counter, #0x00
	mov minutes_counter, #0x00
	mov hours_counter, #0x01
	mov edit_counter, #0x00
	
	mov seconds_counter_2, #0x00
	mov minutes_counter_2, #0x00
	mov hours_counter_2, #0x01
	mov edit_counter_2, #0x00
	
	clr am_pm
	
	Set_Cursor(1, 15)
	Display_char(#'a')
	
	clr am_pm_2
	
	Set_Cursor(2, 15)
	Display_char(#'a')
	
	setb vol_controls
	clr change_flag
	setb onoff_flag
	setb am_pm_clamp
	clr watch_flag
	clr timer_flag

	
	mov Timer0Reload+1, #high(TIMER0_RELOAD)
	mov Timer0Reload+0, #low(TIMER0_RELOAD)
	
	setb TR2
	
    
	; After initialization the program stays in this 'forever' loop
loop:


	mov a, seconds_counter
	
	cjne a, #60h, sec_check
		mov seconds_counter, #0x00
	
		clr a
		mov a, minutes_counter
		add a, #0x01
		da a
		mov minutes_counter, a
	
		
	sec_check:
	
		mov a, minutes_counter
		cjne a, #60h, min_check
	
			mov minutes_counter, #0x00
			
			clr a
			mov a, hours_counter
			add a, #0x01
			da a
			mov hours_counter, a
			
		min_check:
			mov a, hours_counter
			
			cjne a, #11h, hour_check_3
			clr am_pm_clamp
			hour_check_3:
			
			cjne a, #12h, hour_check_2
			
			jb am_pm_clamp, hour_check_2
			
				setb am_pm_clamp
	
				cpl am_pm
				jb am_pm, am_pm_check
					Set_Cursor(1, 15)
					Display_char(#'a')
					sjmp am_pm_done
				am_pm_check:
					Set_Cursor(1, 15)
					Display_char(#'p')
				am_pm_done:
				
			hour_check_2:
				
			cjne a, #13h, hour_check
	
				mov hours_counter, #0x01
			
	
			hour_check:
	
	;Button start --------------------------------------------
	
	jb watch_flag, continue_watch_flag_2
	sjmp continue_watch_flag_2_1
	continue_watch_flag_2:
	ljmp loop_watch
	continue_watch_flag_2_1:
	
	jb timer_flag, continue_timer_flag_2
	sjmp continue_timer_flag_2_1
	continue_timer_flag_2:
	ljmp loop_timer
	continue_timer_flag_2_1:
	
	jb CHANGE_BUTTON, continue_change_1
	sjmp continue_change_1_1
	continue_change_1:
	ljmp change_check
	continue_change_1_1:
	Wait_Milli_Seconds(#50)
	jb CHANGE_BUTTON, continue_change_2
	sjmp continue_change_2_1
	continue_change_2:
	ljmp change_check
	continue_change_2_1:
	jnb CHANGE_BUTTON, $
	
		cpl change_flag
		jb change_flag, change_flag_check
			Set_Cursor(1, 1)
    		Send_Constant_String(#Blank_Message_2)
    		Wait_Milli_Seconds(#200)
			Set_Cursor(1, 1)
    		Send_Constant_String(#Clock_Message_2)
    		sjmp change_flag_done
    	change_flag_check:
    		Set_Cursor(2, 1)
    		Send_Constant_String(#Blank_Message_2)
    		Wait_Milli_Seconds(#200)
    		Set_Cursor(2, 1)
    		Send_Constant_String(#Alarm_Message_2)
    	change_flag_done:	
		
  	change_check:
  	
; TIMER BUTTON CHECK ----------------------------------------------------
  	
  	
  	loop_timer:
  	
  	jb change_flag, continue_timer_flag_1
	ljmp loop_watch
	continue_timer_flag_1:
	
	jb UP_BUTTON, continue_timer_1
	sjmp continue_timer_1_1
	continue_timer_1:
	ljmp timer_check_1
	continue_timer_1_1:
	Wait_Milli_Seconds(#50)
	jb UP_BUTTON, continue_timer_2
	sjmp continue_timer_2_1
	continue_timer_2:
	ljmp timer_check_1
	continue_timer_2_1:
	jnb UP_BUTTON, $
	
		cpl timer_flag
		
		jb timer_flag, timer_flag_check_1
		sjmp timer_flag_check_3
		timer_flag_check_1:
		ljmp timer_flag_check_2
		timer_flag_check_3:
		
			Set_Cursor(1, 1)
		 	Send_Constant_String(#Clock_Message)
		 	
		 	mov seconds_counter, #0x00
			mov minutes_counter, #0x00
			mov hours_counter, #0x01
			
			mov seconds_counter_2, #0x00
			mov minutes_counter_2, #0x00
			mov hours_counter_2, #0x01
			
			setb onoff_flag
			
			jb am_pm, am_pm_check_timer
			
				Set_Cursor(1, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_timer
				
			am_pm_check_timer:
			
				Set_Cursor(1, 15)
				Display_char(#'p')
			
			am_pm_done_timer:
		 	
		 	Set_Cursor(2, 1)
		 	Send_Constant_String(#Alarm_Message)
		 	
		 	Set_Cursor(2, 7)
			Display_BCD(hours_counter_2)
		 	
		 	Set_Cursor(2, 10)
			Display_BCD(minutes_counter_2)
			
			Set_Cursor(2, 13)
			Display_BCD(seconds_counter_2)
			
			jb am_pm_2, am_pm_check_timer_2
			
				Set_Cursor(2, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_timer_2
				
			am_pm_check_timer_2:
			
				Set_Cursor(2, 15)
				Display_char(#'p')
			
			am_pm_done_timer_2:
			
		 	ljmp timer_check_1
		 	

		timer_flag_check_2:
		
		setb onoff_flag
		 	
		Set_Cursor(1, 1)	
		Send_Constant_String(#Timer_Message)
		
		Set_Cursor(2, 1)
		Send_Constant_String(#Clear_Message)
		
		Set_Cursor(2, 3)
		Send_Constant_String(#Set_Message)
		
		mov seconds_counter, #0x00
		mov minutes_counter, #0x00
		mov hours_counter, #0x00
		
		mov seconds_counter_2, #0x00
		mov minutes_counter_2, #0x01
		mov hours_counter_2, #0x00
		
		
		Set_Cursor(2, 7)
		Display_BCD(hours_counter_2)
	 	
	 	Set_Cursor(2, 10)
		Display_BCD(minutes_counter_2)
		
		Set_Cursor(2, 13)
		Display_BCD(seconds_counter_2)
		
		clr TR2
	
	timer_check_1:
	
; TIMER CHECK CHECK ----------------------------------------------------
	
	jb timer_flag, continue_timer_flag
	ljmp edit_loop_1
	continue_timer_flag:
	
	
		jb CHANGE_BUTTON, reset_timer
		Wait_Milli_Seconds(#50)
		jb CHANGE_BUTTON, reset_timer
		jnb CHANGE_BUTTON, $
		
			clr TR2
			setb onoff_flag
			mov seconds_counter, #0x00
			mov minutes_counter, #0x00
			mov hours_counter, #0x00
		
		reset_timer:
		
		
		jb onoff_flag, stop_timer
		
		setb TR2
		sjmp start_timer
			
		stop_timer:
		
		clr TR2
		
		start_timer:
	
		ljmp edit_loop_2
	

; WATCH BUTTON CHECK ----------------------------------------------------


	loop_watch:
	
	jb change_flag, continue_change_flag_3
	sjmp continue_change_flag_3_1
	continue_change_flag_3:
	ljmp watch_check_1
	continue_change_flag_3_1:
	
	jb UP_BUTTON, continue_watch_1
	sjmp continue_watch_1_1
	continue_watch_1:
	ljmp watch_check_1
	continue_watch_1_1:
	Wait_Milli_Seconds(#50)
	jb UP_BUTTON, continue_watch_2
	sjmp continue_watch_2_1
	continue_watch_2:
	ljmp watch_check_1
	continue_watch_2_1:
	jnb UP_BUTTON, $
	
		cpl watch_flag
		
		jb watch_flag, watch_flag_check_1
		sjmp watch_flag_check_3
		watch_flag_check_1:
		ljmp watch_flag_check_2
		watch_flag_check_3:
		
			Set_Cursor(1, 1)
		 	Send_Constant_String(#Clock_Message)
		 	
		 	mov seconds_counter, #0x00
			mov minutes_counter, #0x00
			mov hours_counter, #0x01
			
			jb am_pm, am_pm_check_watch
			
				Set_Cursor(1, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_watch
				
			am_pm_check_watch:
			
				Set_Cursor(1, 15)
				Display_char(#'p')
			
			am_pm_done_watch:
		 	
		 	Set_Cursor(2, 1)
		 	Send_Constant_String(#Alarm_Message)
		 	
		 	Set_Cursor(2, 7)
			Display_BCD(hours_counter_2)
		 	
		 	Set_Cursor(2, 10)
			Display_BCD(minutes_counter_2)
			
			Set_Cursor(2, 13)
			Display_BCD(seconds_counter_2)
			
			jb am_pm_2, am_pm_check_watch_2
			
				Set_Cursor(2, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_watch_2
				
			am_pm_check_watch_2:
			
				Set_Cursor(2, 15)
				Display_char(#'p')
			
			am_pm_done_watch_2:
			
		 	ljmp watch_check_1
		 	

		watch_flag_check_2:
		 	
		Set_Cursor(1, 1)	
		Send_Constant_String(#Watch_Message)
		
		Set_Cursor(2, 1)
		Send_Constant_String(#Clear_Message)
		
		mov seconds_counter, #0x00
		mov minutes_counter, #0x00
		mov hours_counter, #0x00
		
		Set_Cursor(1,16)
		Display_char(#1)
		
		clr TR2
	
	watch_check_1:
	
; WATCH CHECK CHECK == 1 ----------------------------------------------------
	
	jb watch_flag, continue_watch_flag
	ljmp edit_loop_1
	continue_watch_flag:

		jb CHANGE_BUTTON, reset_watch
		Wait_Milli_Seconds(#50)
		jb CHANGE_BUTTON, reset_watch
		jnb CHANGE_BUTTON, $
		
			clr TR2
			mov seconds_counter, #0x00
			mov minutes_counter, #0x00
			mov hours_counter, #0x00
			
			Set_Cursor(1,16)
			Display_char(#1)
		
		reset_watch:
		
		jb ONOFF_BUTTON, start_watch
		Wait_Milli_Seconds(#50)
		jb ONOFF_BUTTON, start_watch
		jnb ONOFF_BUTTON, $
		
			cpl TR2
			
			jb TR2, skip_write_watch
			Set_Cursor(1,16)
			Display_char(#1)
			sjmp done_write_watch
			skip_write_watch:
			Set_Cursor(1,16)
			Display_char(#0)
			done_write_watch:
		
		start_watch:
		
		jb EDIT_BUTTON, lap_watch
		Wait_Milli_Seconds(#50)
		jb EDIT_BUTTON, lap_watch
		jnb EDIT_BUTTON, $
		
			Set_Cursor(2, 3)
			Send_Constant_String(#Lap_Message)
			
			Set_Cursor(2, 7)
			Display_BCD(hours_counter)
			 	
		 	Set_Cursor(2, 10)
			Display_BCD(minutes_counter)
			
			Set_Cursor(2, 13)
			Display_BCD(seconds_counter)
		
		lap_watch:
	 	
	 	jb DOWN_BUTTON, reset_lab_watch
		Wait_Milli_Seconds(#50)
		jb DOWN_BUTTON, reset_lab_watch
		jnb DOWN_BUTTON, $
		
			Set_Cursor(2, 1)
			Send_Constant_String(#Clear_Message)
		
		reset_lab_watch:
	 	
	ljmp loop_write
	
	
	
; EDIT CHECK ----------------------------------------------------
	edit_loop_1:
	
	
	
	jb change_flag, continue_change_flag_1
	sjmp continue_change_flag_1_1
	continue_change_flag_1:
	ljmp edit_loop_2
	continue_change_flag_1_1:
	
	jb EDIT_BUTTON, continue_edit_1
	sjmp continue_edit_1_1
	continue_edit_1:
	ljmp loop_vol
	continue_edit_1_1:
	Wait_Milli_Seconds(#50)
	jb EDIT_BUTTON, continue_edit_2
	sjmp continue_edit_2_1
	continue_edit_2:
	ljmp loop_vol
	continue_edit_2_1:
	jnb EDIT_BUTTON, $
		
	Set_Cursor(1, 16)
	Display_char(#4)

	Set_Cursor(1, 7)
	Send_Constant_String(#Blank_Message)
	Wait_Milli_Seconds(#200)
	Set_Cursor(1, 7)
	Display_BCD(hours_counter)
	
	clr TR2
	
	
	edit_loop:
	


		jb EDIT_BUTTON, continue_edit_3
		sjmp continue_edit_3_1
		continue_edit_3:
		ljmp edit_check_0
		continue_edit_3_1:
		Wait_Milli_Seconds(#50)
		jb EDIT_BUTTON, continue_edit_4
		sjmp continue_edit_4_1
		continue_edit_4:
		ljmp edit_check_0
		continue_edit_4_1:
		jnb EDIT_BUTTON, $
		
			clr a
			mov a, edit_counter
			add a, #0x01
			mov edit_counter, a
			
			cjne a, #0x01, edit_check_2_1_1
		
				Set_Cursor(1, 10)
				Send_Constant_String(#Blank_Message)
				Wait_Milli_Seconds(#200)
				Set_Cursor(1, 10)
				Display_BCD(minutes_counter)
			
			edit_check_2_1_1:

			cjne a, #0x02, edit_check_3_1_1
				Set_Cursor(1, 13)
				Send_Constant_String(#Blank_Message)
				Wait_Milli_Seconds(#200)
				Set_Cursor(1, 13)
				Display_BCD(seconds_counter)
			edit_check_3_1_1:
			
			cjne a, #0x03, edit_check_4_1_1
				Set_Cursor(1, 15)
				Display_char(#' ')
				Wait_Milli_Seconds(#200)
				jb am_pm, am_pm_check_3
				
					Set_Cursor(1, 15)
					Display_char(#'a')
				
				sjmp am_pm_done_3
					
				am_pm_check_3:
				
					Set_Cursor(1, 15)
					Display_char(#'p')
				
				am_pm_done_3:
			
			edit_check_4_1_1:
			
		edit_check_0:
		
		mov a, edit_counter
		
		cjne a, #0x00, edit_check_1
			Set_Cursor(1, 7)
			Display_BCD(hours_counter)
			
			jb UP_BUTTON, edit_check_1_1
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_1_1
			jnb UP_BUTTON, $
			
			mov a, hours_counter
			cjne a, #12h, edit_check_1_2
			mov hours_counter, #0x01
			sjmp edit_check_1_1
			edit_check_1_2:
			
			add a, #0x01
			da a
			mov hours_counter, a
			
			edit_check_1_1:
			
			jb DOWN_BUTTON, edit_check_1
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_1
			jnb DOWN_BUTTON, $
			
			
			mov a, hours_counter
			cjne a, #01h, edit_check_1_3
			mov hours_counter, #12h
			sjmp edit_check_1
			edit_check_1_3:
			
			add a, #0x99
			da a
			mov hours_counter, a
			
		edit_check_1:
		
		mov a, edit_counter
		
		cjne a, #0x01, edit_check_2
			Set_Cursor(1, 10)
			Display_BCD(minutes_counter)
			
			
			jb UP_BUTTON, edit_check_2_1
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_2_1
			jnb UP_BUTTON, $
			
			mov a, minutes_counter
			cjne a, #59h, edit_check_2_2
			mov minutes_counter, #0x00
			sjmp edit_check_2_1
			edit_check_2_2:
			
			add a, #0x01
			da a
			mov minutes_counter, a
			
			edit_check_2_1:

			
			jb DOWN_BUTTON, edit_check_2
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_2
			jnb DOWN_BUTTON, $
			
			mov a, minutes_counter
			cjne a, #00h, edit_check_2_3
			mov minutes_counter, #59h
			sjmp edit_check_2
			edit_check_2_3:
			
			add a, #0x99
			da a
			mov minutes_counter, a
			
		edit_check_2:
		
		mov a, edit_counter
		
		cjne a, #0x02, edit_check_3
			Set_Cursor(1, 13)
			Display_BCD(seconds_counter)
			
			jb UP_BUTTON, edit_check_3_1
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_3_1
			jnb UP_BUTTON, $
			
			mov a, seconds_counter
			cjne a, #59h, edit_check_3_2
			mov seconds_counter, #0x00
			sjmp edit_check_3_1
			edit_check_3_2:
			
			add a, #0x01
			da a
			mov seconds_counter, a
			
			edit_check_3_1:

			
			jb DOWN_BUTTON, edit_check_3
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_3
			jnb DOWN_BUTTON, $
			
			mov a, seconds_counter
			cjne a, #00h, edit_check_3_3
			mov seconds_counter, #59h
			sjmp edit_check_3
			edit_check_3_3:
			
			add a, #0x99
			da a
			mov seconds_counter, a
			
		edit_check_3:
		
		mov a, edit_counter
		
		cjne a, #0x03, edit_check_4
		
			jb am_pm, am_pm_check_2
			
				Set_Cursor(1, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_2
				
			am_pm_check_2:
			
				Set_Cursor(1, 15)
				Display_char(#'p')
			
			am_pm_done_2:
			
			jb UP_BUTTON, edit_check_4_1
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_4_1
			jnb UP_BUTTON, $
			
				cpl am_pm
		
			edit_check_4_1:
		
			jb DOWN_BUTTON, edit_check_4
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_4
			jnb DOWN_BUTTON, $
			
				cpl am_pm
		
		edit_check_4:
		
		mov a, edit_counter
		
		cjne a, #0x04, continue_edit_5
		
	sjmp edit_exit	
	
	continue_edit_5:
	
	ljmp edit_loop
	
	edit_exit:
	
	mov edit_counter, #0x00
	
	Set_Cursor(1, 16)
	Display_char(#' ')
	 
	setb TR2                ; Start timer 2
	
	
; EDIT CONTROLS 2 -------------------------------------------------------------------------------
	edit_loop_2:
	
	jb change_flag, continue_change_flag_2
	ljmp loop_vol
	continue_change_flag_2:
	
	
	
	jb EDIT_BUTTON, continue_edit_1__2
	sjmp continue_edit_1_1__2
	continue_edit_1__2:
	ljmp loop_vol
	continue_edit_1_1__2:
	Wait_Milli_Seconds(#50)
	jb EDIT_BUTTON, continue_edit_2__2
	sjmp continue_edit_2_1__2
	continue_edit_2__2:
	ljmp loop_vol
	continue_edit_2_1__2:
	jnb EDIT_BUTTON, $
		
	Set_Cursor(2, 16)
	Display_char(#4)	

	Set_Cursor(2, 7)
	Send_Constant_String(#Blank_Message)
	Wait_Milli_Seconds(#200)
	Set_Cursor(2, 7)
	Display_BCD(hours_counter_2)
	
	
	clr TR2
	
	edit_loop__2:
	


		jb EDIT_BUTTON, continue_edit_3__2
		sjmp continue_edit_3_1__2
		continue_edit_3__2:
		ljmp edit_check_0__2
		continue_edit_3_1__2:
		Wait_Milli_Seconds(#50)
		jb EDIT_BUTTON, continue_edit_4__2
		sjmp continue_edit_4_1__2
		continue_edit_4__2:
		ljmp edit_check_0__2
		continue_edit_4_1__2:
		jnb EDIT_BUTTON, $
		
			clr a
			mov a, edit_counter_2
			add a, #0x01
			mov edit_counter_2, a
			
			cjne a, #0x01, edit_check_2_1_1__2
		
				Set_Cursor(2, 10)
				Send_Constant_String(#Blank_Message)
				Wait_Milli_Seconds(#200)
				Set_Cursor(2, 10)
				Display_BCD(minutes_counter_2)
			
			edit_check_2_1_1__2:

			cjne a, #0x02, edit_check_3_1_1__2
				Set_Cursor(2, 13)
				Send_Constant_String(#Blank_Message)
				Wait_Milli_Seconds(#200)
				Set_Cursor(2, 13)
				Display_BCD(seconds_counter_2)
			edit_check_3_1_1__2:
			
			jb timer_flag, edit_check_4_1_1__2 ;skip if in timer
			
			cjne a, #0x03, edit_check_4_1_1__2
				Set_Cursor(2, 15)
				Display_char(#' ')
				Wait_Milli_Seconds(#200)
				jb am_pm_2, am_pm_check_3__2
				
					Set_Cursor(2, 15)
					Display_char(#'a')
				
				sjmp am_pm_done_3__2
					
				am_pm_check_3__2:
				
					Set_Cursor(2, 15)
					Display_char(#'p')
				
				am_pm_done_3__2:
			
			edit_check_4_1_1__2:
			
		edit_check_0__2:
		
		mov a, edit_counter_2
		
		cjne a, #0x00, edit_check_1__2
			Set_Cursor(2, 7)
			Display_BCD(hours_counter_2)
			
			jb UP_BUTTON, edit_check_1_1__2
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_1_1__2
			jnb UP_BUTTON, $
			
			mov a, hours_counter_2
			
			jb timer_flag, ampm_skip_3 ;skips in timer -----------
			
			cjne a, #12h, edit_check_1_2__2
			
			
			mov hours_counter_2, #01h 
			sjmp ampm_skip_3_1
			
			ampm_skip_3:
			
			cjne a, #99h, edit_check_1_2__2
			mov hours_counter_2, #00h
			
			ampm_skip_3_1: ;skips in timer -----------
			
			sjmp edit_check_1_1__2
			edit_check_1_2__2:
			
			add a, #0x01
			da a
			mov hours_counter_2, a
			
			edit_check_1_1__2:

			
			jb DOWN_BUTTON, edit_check_1__2
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_1__2
			jnb DOWN_BUTTON, $
			
			mov a, hours_counter_2
			jb timer_flag, ampm_skip_2 ;skips in timer -----------
			
			cjne a, #01h, edit_check_1_3__2
			
			mov hours_counter_2, #12h
			sjmp ampm_skip_2_1
			
			ampm_skip_2:
			
			cjne a, #00h, edit_check_1_3__2
			mov hours_counter_2, #99h
			ampm_skip_2_1: ;skips in timer -----------
			
			sjmp edit_check_1__2
			edit_check_1_3__2:
			
			add a, #0x99
			da a
			mov hours_counter_2, a
			
		edit_check_1__2:
		
		mov a, edit_counter_2
		
		cjne a, #0x01, edit_check_2__2
			Set_Cursor(2, 10)
			Display_BCD(minutes_counter_2)
			
			jb UP_BUTTON, edit_check_2_1__2
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_2_1__2
			jnb UP_BUTTON, $
			
			mov a, minutes_counter_2
			cjne a, #59h, edit_check_2_2__2
			mov minutes_counter_2, #0x00
			sjmp edit_check_2_1__2
			edit_check_2_2__2:
			
			add a, #0x01
			da a
			mov minutes_counter_2, a
			
			edit_check_2_1__2:
			
			
			jb DOWN_BUTTON, edit_check_2__2
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_2__2
			jnb DOWN_BUTTON, $
			
			mov a, minutes_counter_2
			cjne a, #00h, edit_check_2_3__2
			mov minutes_counter_2, #59h
			sjmp edit_check_2__2
			edit_check_2_3__2:
			
			add a, #0x99
			da a
			mov minutes_counter_2, a
			
		edit_check_2__2:
		
		mov a, edit_counter_2
		
		cjne a, #0x02, edit_check_3__2
			Set_Cursor(2, 13)
			Display_BCD(seconds_counter_2)
			
			
			jb UP_BUTTON, edit_check_3_1__2
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_3_1__2
			jnb UP_BUTTON, $
			
			mov a, seconds_counter_2
			cjne a, #59h, edit_check_3_2__2
			mov seconds_counter_2, #0x00
			sjmp edit_check_3_1__2
			edit_check_3_2__2:
			
			add a, #0x01
			da a
			mov seconds_counter_2, a
			
			edit_check_3_1__2:

			
			jb DOWN_BUTTON, edit_check_3__2
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_3__2
			jnb DOWN_BUTTON, $
			
			mov a, seconds_counter_2
			cjne a, #00h, edit_check_3_3__2
			mov seconds_counter_2, #59h
			sjmp edit_check_3__2
			edit_check_3_3__2:
			
			add a, #0x99
			da a
			mov seconds_counter_2, a
			
		edit_check_3__2:
		
		jb timer_flag, ampm_skip ;skip if in timer-----------
		
			sjmp ampm_continue
			
		ampm_skip:
		
			mov a, edit_counter_2
			cjne a, #0x03, continue_edit_5__2
			
			ljmp edit_exit__2	
		
		ampm_continue: ;skip if in timer-------------
		
		mov a, edit_counter_2
		
		cjne a, #0x03, edit_check_4__2
		
			jb am_pm_2, am_pm_check_2__2
			
				Set_Cursor(2, 15)
				Display_char(#'a')
			
				sjmp am_pm_done_2__2
				
			am_pm_check_2__2:
			
				Set_Cursor(2, 15)
				Display_char(#'p')
			
			am_pm_done_2__2:
			
			jb UP_BUTTON, edit_check_4_1__2
			Wait_Milli_Seconds(#50)
			jb UP_BUTTON, edit_check_4_1__2
			jnb UP_BUTTON, $
			
				cpl am_pm_2
		
			edit_check_4_1__2:
		
			jb DOWN_BUTTON, edit_check_4__2
			Wait_Milli_Seconds(#50)
			jb DOWN_BUTTON, edit_check_4__2
			jnb DOWN_BUTTON, $
			
				cpl am_pm_2
		
		edit_check_4__2:
		
		mov a, edit_counter_2
		
		cjne a, #0x04, continue_edit_5__2
		
	sjmp edit_exit__2	
	
	continue_edit_5__2:
	
	ljmp edit_loop__2
	
	edit_exit__2:
	
	mov edit_counter_2, #0x00
	
	Set_Cursor(2, 16)
	Display_char(#' ')
	
	jb timer_flag, TR2_skip_1
	
	setb TR2
	
	TR2_skip_1:
	 
	; VOLUME CONTROLSSSSS ---------------------------------------------------
loop_vol:
	jb DOWN_BUTTON, loop_onoff
	Wait_Milli_Seconds(#50)
	jb DOWN_BUTTON, loop_onoff
	jnb DOWN_BUTTON, $
	
	cpl vol_controls
	
	jb vol_controls, vol_2
	
	clr  ET0          ; disable Timer0 interrupt
    clr  TR0          ; stop Timer0

    mov  Timer0Reload+1, #high(TONE_4096)
    mov  Timer0Reload+0, #low(TONE_4096)

    setb TR0          ; restart Timer0
    setb ET0          ; re-enable interrupt
    
    ljmp loop_a  
    
    vol_2:
    	
	clr  ET0          ; disable Timer0 interrupt
    clr  TR0          ; stop Timer0

    mov  Timer0Reload+1, #high(TONE_1024)
    mov  Timer0Reload+0, #low(TONE_1024)

    setb TR0          ; restart Timer0
    setb ET0          ; re-enable interrupt
    
loop_onoff:

	jb ONOFF_BUTTON, loop_alarm_check
	Wait_Milli_Seconds(#50)
	jb ONOFF_BUTTON, loop_alarm_check
	jnb ONOFF_BUTTON, $
	
	cpl onoff_flag
	
loop_alarm_check:
	
	jb onoff_flag, skip_write_vol
	
	jb vol_controls, skip_write_2
	Set_Cursor(1,16)
	Display_char(#3)
	sjmp done_write_2
	skip_write_2:
	Set_Cursor(1,16)
	Display_char(#2)
	done_write_2:
	
	clr a
	mov a, seconds_counter
	cjne a, seconds_counter_2, skip_alarm
		mov a, minutes_counter
		cjne a, minutes_counter_2, skip_alarm
			mov a, hours_counter
			cjne a, hours_counter_2, skip_alarm
			
			    jb timer_flag, TR2_skip_4 ;timer skip------------ 
			
				jb am_pm, am_pm_is_1
				jb am_pm_2, skip_alarm
				sjmp equal_bits
				
				am_pm_is_1:
				jb am_pm_2, equal_bits

				sjmp skip_alarm
				
				TR2_skip_4: ;timer skip------------
				
				equal_bits:
					setb TR0
    				setb ET0
    				clr TR2
					ljmp alarm_loop
					
	skip_write_vol:				
		
	Set_Cursor(1,16)
	Display_char(#' ')
					
	skip_alarm:
	
	clr  ET0
    clr  TR0
    
    jb timer_flag, TR2_skip_3 ; timer skip------------
    
	setb TR2
	
	TR2_skip_3: ; timer skip--------------
	
	ljmp loop_a
	
	alarm_loop:
	
		jb onoff_flag, skip_alarm
		
	
		
		jb ONOFF_BUTTON, alarm_loop_continue
		Wait_Milli_Seconds(#50)
		jb ONOFF_BUTTON, alarm_loop_continue
		jnb ONOFF_BUTTON, $
	
		setb onoff_flag
		
		alarm_loop_continue:
		
		jb DOWN_BUTTON, alarm_loop_continue_2
		Wait_Milli_Seconds(#50)
		jb DOWN_BUTTON, alarm_loop_continue_2
		jnb DOWN_BUTTON, $
		
		clr a
		mov a, minutes_counter_2
		add a, #0x05
		da a
		mov minutes_counter_2, a
		
		Set_Cursor(2, 10)
		Display_BCD(minutes_counter_2)
		
		ljmp skip_alarm
		
		alarm_loop_continue_2:
	
    ljmp alarm_loop	
loop_a:
	
	jb onoff_flag, skip_write
	Set_Cursor(2,16)
	Display_char(#0)
	sjmp done_write
	skip_write:
	Set_Cursor(2,16)
	Display_char(#1)
	done_write:
	
	
loop_write:

	Set_Cursor(1, 13)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(seconds_counter)
	Set_Cursor(1, 10)
	Display_BCD(minutes_counter)
	Set_Cursor(1, 7)
	Display_BCD(hours_counter)
	
	jb  second_flag, continue   ; if flag = 1, skip jump
	ljmp loop                   ; long jump (any distance)
continue:
loop_b:
    clr second_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 2
	
    ljmp loop
END
