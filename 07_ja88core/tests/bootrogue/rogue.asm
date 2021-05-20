        ;
        ; bootRogue game in 512 bytes (boot sector)
        ;
        ; by Oscar Toledo G.
        ; http://nanochess.org/
        ;
        ; (c) Copyright 2019 Oscar Toledo G.
        ;
        ; Creation date: Sep/19/2019. Generates room boxes.
        ; Revision date: Sep/20/2019. Connect rooms. Allows to navigate.
        ; Revision date: Sep/21/2019. Added ladders to go down/up. Shows
        ;                             Amulet of Yendor at level 26. Added
        ;                             circle of light.
        ; Revision date: Sep/22/2019. Creates monsters and items. Now has
        ;                             hp/exp. Food, armor, weapon, and traps
        ;                             works. Added battles. 829 bytes.
        ; Revision date: Sep/23/2019. Lots of optimization. 643 bytes.
        ; Revision date: Sep/24/2019. Again lots of optimization. 596 bytes.
        ; Revision date: Sep/25/2019. Many optimizations. 553 bytes.
        ; Revision date: Sep/26/2019. The final effort. 510 bytes.
        ; Revision date: Sep/27/2019. The COM file exits to DOS instead of halting.
        ;

        CPU 8086

ROW_WIDTH:      EQU 0x00A0      ; Width in bytes of each video row
BOX_MAX_WIDTH:  EQU 23          ; Max width of a room box
BOX_MAX_HEIGHT: EQU 6           ; Max height of a room box
BOX_WIDTH:      EQU 26          ; Width of box area in screen
BOX_HEIGHT:     EQU 8           ; Height of box area in screen

        ; See page 45 of my book
LIGHT_COLOR:    EQU 0x06        ; Light color (brown, dark yellow on emu)
HERO_COLOR:     EQU 0x0e        ; Hero color (yellow)

        ; See page 179 of my book
GR_VERT:        EQU 0xba        ; Vertical line graphic
GR_TOP_RIGHT:   EQU 0xbb        ; Top right graphic
GR_BOT_RIGHT:   EQU 0xbc        ; Bottom right graphic
GR_BOT_LEFT:    EQU 0xc8        ; Bottom left graphic
GR_TOP_LEFT:    EQU 0xc9        ; Top left graphic
GR_HORIZ:       EQU 0xcd        ; Horizontal line graphic

GR_TUNNEL:      EQU 0xb1        ; Tunnel graphic (shaded block)
GR_DOOR:        EQU 0xce        ; Door graphic (crosshair graphic)
GR_FLOOR:       EQU 0xfa        ; Floor graphic (middle point)

GR_HERO:        EQU 0x01        ; Hero graphic (smiling face)

GR_LADDER:      EQU 0xf0        ; Ladder graphic
GR_TRAP:        EQU 0x04        ; Trap graphic (diamond)
GR_FOOD:        EQU 0x05        ; Food graphic (clover)
GR_ARMOR:       EQU 0x08        ; Armor graphic (square with hole in center)
GR_YENDOR:      EQU 0x0c        ; Amulet of Yendor graphic (Female sign)
GR_GOLD:        EQU 0x0f        ; Gold graphic (asterisk, like brightness)
GR_WEAPON:      EQU 0x18        ; Weapon graphic (up arrow)

YENDOR_LEVEL:   EQU 26          ; Level of appearance for Amulet of Yendor

    %ifdef com_file
        org 0x0100
    %else
        org 0x7c00
    %endif

        ;
        ; Sorted by order of PUSH instructions
        ;
rnd:    equ 0x0008      ; Random seed (used 4 times)
starve: equ 0x0006      ; Starve counter (used once)
hp:     equ 0x0004      ; Current HP (used 2 times)
level:  equ 0x0003      ; Current level (starting at 0x01) (used 3 times)
yendor: equ 0x0002      ; 0x01 = Not found. 0xff = Found. (Used 2 times)
armor:  equ 0x0001      ; Armor level (used 2 times)
weapon: equ 0x0000      ; Weapon level (used 2 times)

        ;
        ; Start of the adventure!
        ;
start:
        mov al,$12
        push ax         ; Setup pseudorandom number generator
        mov ax,32
        push ax         ; starve
        push ax         ; hp
        mov al,1
        push ax         ; yendor (low byte) + level (high byte)
        push ax         ; weapon (low byte) + armor (high byte)
        inc ax          ; ax = 0x0002 (it was 0x0001)
        int 0x10
        mov ax,0xb800   ; Text video segment
        mov ds,ax
        mov es,ax

        mov si,random   ; SI as a space saver for CALL

        mov bp,sp       ; Using BP because it implies SS and vars are on stack.

generate_dungeon:

        ;
        ; Advance to next level (can go deeper or higher)
        ;
        mov bl,[bp+yendor]
        add [bp+level],bl
    %ifdef com_file
        jne .0
        jmp quit        ; Stop if level zero is reached
.0:
    %else
        je $            ; Stop if level zero is reached
    %endif

        ;
        ; Select a maze for the dungeon
        ;
        ; There are many combinations of values that generate at least
        ; 16 mazes in order to avoid a table.
        ;
        mov ax,[bp+rnd]
        and ax,0x4182
        or ax,0x1a6d
        xchg ax,dx

        ;
        ; Clean the screen to black over black (it hides the maze)
        ;
        xor ax,ax
        xor di,di
        mov ch,0x08
        ;rep stosw

        ;
        ; Draw the nine rooms
        ;
.7:
        push ax
        call fill_room
        pop ax
        add ax,BOX_WIDTH*2
        cmp al,0x9c             ; Finished drawing three rooms?
        jne .6                  ; No, jump
                                ; Yes, go to following row
        add ax,ROW_WIDTH*BOX_HEIGHT-BOX_WIDTH*3*2
.6:
        cmp ax,ROW_WIDTH*BOX_HEIGHT*3
        jb .7

        ;
        ; Put the ladder at a random corner room
        ;
        shl word [bp+rnd],1
        mov ax,3*ROW_WIDTH+12*2
        mov bx,19*ROW_WIDTH+12*2
        jnc .2
        xchg ax,bx
.2:     jns .8
        add ax,BOX_WIDTH*2*2
.8:
        xchg ax,di

        mov byte [di],GR_LADDER

        ;
        ; If a deep level has been reached then put the Amulet of Yendor
        ;
        cmp byte [bp+level],YENDOR_LEVEL
        jb .1
        mov byte [bx],GR_YENDOR
.1:
        ;
        ; Setup hero start
        ;
        mov di,11*ROW_WIDTH+38*2
        ;
        ; Main game loop
        ;
game_loop:
        mov ax,game_loop        ; Force to repeat, the whole loop...
        push ax                 ; ...ends with ret.

        ;
        ; Circle of light around the player (3x3)
        ;
        mov bx,0x0005                   ; BX values
.1:     dec bx
        dec bx                          ; -1 1 3 -0x00a0
        mov al,LIGHT_COLOR
        mov [bx+di-ROW_WIDTH],al        ; -1(1)3
        mov [bx+di],al
        mov [bx+di+ROW_WIDTH],al        ; -1 1 3 +0x00a0
        jns .1

        ;
        ; Show our hero
        ;
        push word [di]          ; Save character and attribute under
        mov word [di],HERO_COLOR*256+GR_HERO
        add byte [bp+starve],2  ; Cannot use INC because it needs Carry set
        sbb ax,ax               ; HP down 1 every 128 steps
        call add_hp             ; Update stats
    ;   mov ah,0x00             ; Comes here with ah = 0
        int 0x16                ; Read keyboard
        pop word [di]           ; Restore character and attribute under

        mov al,ah
    %ifdef com_file
        cmp al,0x01
        je quit                 ; Exit if Esc key is pressed
    %endif

        sub al,0x4c
        mov ah,0x02             ; Left/right multiplies by 2
        cmp al,0xff             ; Going left (scancode 0x4b)
        je .2
        cmp al,0x01             ; Going right (scancode 0x4d)
        je .2
        cmp al,0xfc             ; Going up (scancode 0x48)
        je .3
        cmp al,0x04             ; Going down (scancode 0x50)
        jne move_cancel
.3:
        mov ah,0x28             ; Up/down multiplies by 40
.2:
        imul ah                 ; Signed multiplication

        xchg ax,bx              ; bx = displacement offset
        mov al,[di+bx]          ; Read the target contents
        ;
        ; All the things that can exist on screen start with GR_* (17 things)
        ; So no need to account for all cases.
        ; We won't ever find GR_HERO so there are 16 things to look for.
        ;
        cmp al,GR_LADDER        ; GR_LADDER?
        je ladder_found
        ; 15 things to look for (plus zero and monsters)
        ; Anything > GR_TUNNEL and < GR_DOOR is a wall
        cmp al,GR_DOOR          ; GR_DOOR?
        jnc .4
        cmp al,GR_TUNNEL        ; GR_TUNNEL?
        ja move_cancel
.4:
        ; 9 things to look for (plus zero and monsters)
        cmp al,GR_TRAP          ; GR_TRAP?
        jb move_cancel          ; < it must be blank, cancel movement
        ; Move player
        lea di,[di+bx]          ; Do move.
        mov bh,0x06             ; Random range for GR_FOOD and GR_TRAP
        je trap_found           ; = Yes, went over trap
        ; 8 things to look for (plus monsters)
        cmp al,GR_TUNNEL        ; GR_TUNNEL+GR_DOOR+GR_FLOOR ?
        jnc move_cancel         ; Yes, jump.
        cmp al,GR_WEAPON        ; GR_WEAPON?
        ja battle               ; > it's a monster, so go to battle
        ; Only items at this part of code, so clean floor
        mov byte [di],GR_FLOOR  ; Delete item from floor
        je weapon_found         ; = weapon found
        ; 4 things to look for
        cmp al,GR_ARMOR         ; GR_ARMOR?
        je armor_found          ; Yes, increase armor
        jb food_found           ; < it's GR_FOOD, increase hp
        ; 2 things to look for
        cmp al,GR_GOLD          ; GR_GOLD?
        je move_cancel          ; Yes, simply take it.
        ; At this point 'al' can only be GR_YENDOR
        ; Amulet of Yendor found!
        neg byte [bp+yendor]    ; Now player goes upwards over ladders.
move_cancel:
        ret                     ; Return to main loop.

    %ifdef com_file
quit:
        int 0x20
    %endif

        ;
        ;     I--
        ;   I--
        ; I--
        ;
ladder_found:
        jmp generate_dungeon

        ; ______
        ; I    I
        ; I #X I
        ; I X# I
        ;  \__/
        ;
armor_found:
        inc byte [bp+armor]     ; Increase armor level
        ret

        ;
        ;       /| _____________
        ; (|===|oo>_____________>
        ;       \|
        ;
weapon_found:
        inc byte [bp+weapon]    ; Increase weapon level
        ret

        ;
        ; Aaaarghhhh!
        ;
trap_found:
        call si                 ; Random 1-6
sub_hp: neg ax                  ; Make it negative
        db 0xbb                 ; MOV BX to jump two bytes
        ;
        ;     /--\
        ; ====    I
        ;     \--/
        ;
food_found:
        call si                 ; Random 1-6

add_hp: add ax,[bp+hp]          ; Add to current HP
    %ifdef com_file
        js quit                 ; Exit if Esc key is pressed
    %else
        js $                    ; Stall if dead
    %endif
        mov [bp+hp],ax          ; Update HP.
        ;
        ; Update screen indicator
        ;
        mov bx,0x0f98           ; Point to bottom right corner
        call .1
    %ifdef com_file
        mov al,[bp+weapon]
        call .1
        mov al,[bp+armor]
        call .1
    %endif
        mov al,[bp+level]
.1:
        xor cx,cx               ; CX = Quotient
.2:     inc cx
        sub ax,10               ; Division by subtraction
        jnc .2
        add ax,0x0a3a           ; Convert remainder to ASCII digit + color
        call .3                 ; Put on screen
        xchg ax,cx
        dec ax                  ; Quotient is zero?
        jnz .1                  ; No, jump to show more digits.

.3:     mov [bx],ax
        dec bx
        dec bx
        ret

        ;
        ; Let's battle!!!
        ;
battle:
        and al,0x1f     ; Separate number of monster (1-26)
        shl al,1        ; Make it slightly harder
        mov ah,al       ; Use also as its HP
        xchg ax,dx      ; Its attack is equivalent to its number
        ; Player's attack
.2:
        mov bh,[bp+weapon]      ; Use current weapon level as dice
        call si
        sub dh,al       ; Subtract from monster's HP
        jc .3           ; Killed? yes, jump
        ; Monster's attack
        mov bh,dl       ; Use monster number as dice
        call si
        sub al,[bp+armor]       ; Subtract armor from attack
        jc .4
        call sub_hp     ; Subtract from player's HP
.4:
    ;   mov ah,0x00     ; Comes here with ah = 0
        int 0x16        ; Wait for a key.
        jmp .2          ; Another battle round.

        ;
        ; Monster is dead
        ;
.3:
        mov byte [di],GR_FLOOR  ; Remove from screen
        ret

        ;
        ; Fill a room
        ;
fill_room:
        add ax,(BOX_HEIGHT/2-1)*ROW_WIDTH+(BOX_WIDTH/2)*2
        push ax
        xchg ax,di
        shr dx,1                ; Obtain bit of right connection
        mov ax,0x0000+GR_TUNNEL
        mov cx,BOX_WIDTH
        jnc .3
        push di
        rep stosw               ; Horizontal tunnel
        pop di
.3:
        shr dx,1                ; Obtain bit of down connection
        jnc .5
        mov cl,BOX_HEIGHT
.4:
        stosb                   ; Vertical tunnel
        add di,ROW_WIDTH-1
        loop .4
.5:
        mov bh,BOX_MAX_WIDTH-2
        call si                 ; Get a random width for room.
        xchg ax,cx
        mov bh,BOX_MAX_HEIGHT-2
        call si                 ; Get a random height for room.
        mov ch,al
        shr al,1                ;
        inc ax
        mov ah,ROW_WIDTH
        mul ah
        add ax,cx               ; Now it has a centering offset
        sub ah,ch               ; Better than "mov bx,cx mov bh,0"
        and al,0xfe
        add al,0x04
        pop di
        sub di,ax               ; Subtract from room center
        mov al,GR_TOP_LEFT      ; Draw top row of room
        mov bx,GR_TOP_RIGHT*256+GR_HORIZ
        call fill
.9:
        mov al,GR_VERT          ; Draw intermediate row of room
        mov bx,GR_VERT*256+GR_FLOOR
        call fill
        dec ch
        jns .9
        mov al,GR_BOT_LEFT      ; Draw bottom row of room
        mov bx,GR_BOT_RIGHT*256+GR_HORIZ

        ;
        ; Fill a row on screen for a room
        ;
fill:   push cx                 ; Save CX because it needs CL value again
        push di                 ; Save video position
        call door               ; Left border
.1:     mov al,bl               ; Filler
        call door
        dec cl
        jns .1
        mov al,bh               ; Right border
        call door
        pop di                  ; Restore video position
        pop cx                  ; Restore CX
        add di,0x00a0           ; Goes to next row on screen
        ret

        ;
        ; Draw a room character on screen
        ;
door:
        cmp al,GR_FLOOR         ; Drawing floor?
        jne .3                  ; No, jump
        call si                 ; Get a random number (BH value is GR_VERT)
        cmp al,6                ; Chance of creating a monster
        jnc .11
        add al,[bp+level]       ; More difficult monsters as level is deeper
.9:
        sub al,0x05
        cmp al,0x17             ; Make sure it fits inside ASCII letters
        jge .9
        add al,0x44             ; Offset into ASCII letters
        jmp short .12

.11:
        cmp al,11               ; Chance of creating an item
        xchg ax,bx
        cs mov bl,[si+bx+(items-random-6)]
        xchg ax,bx
        jb .12
        mov al,GR_FLOOR         ; Show only floor.
.12:
.3:
        cmp al,GR_HORIZ
        je .1
        cmp al,GR_VERT
        jne .2
.1:     cmp byte [di],GR_TUNNEL
        jne .2
        mov al,GR_DOOR
.2:     stosb
        inc di
        ret

random:
        mov al,251
        mul byte [bp+rnd]
        add al,83
        mov [bp+rnd],ax

;       rdtsc           ; Would make it dependent on Pentium II
;       in al,(0x40)    ; Only works for slow requirements.

        xor ah,ah
        div bh
        mov al,ah
        cbw
        inc ax
        ret

        ;
        ; Items
        ;
items:
        db GR_FOOD
        db GR_GOLD
        db GR_TRAP
        db GR_WEAPON
        db GR_ARMOR

    %ifdef com_file
    %else
        times 510-($-$$) db 0x4f
        db 0x55,0xaa            ; Make it a bootable sector
    %endif

