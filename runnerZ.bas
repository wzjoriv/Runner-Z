' =========================================================================
' IntyBASIC SDK Project: RunnerZ V.1
' -------------------------------------------------------------------------
'     Programmer: Josue N Rivera
'     Created:    12/14/2017
'     Updated:    12/14/2017
'
' -------------------------------------------------------------------------
' History:
' 12/14/2017 - runnerZ project created.
' 12/15/2017 - power ups added and the ability to jump.
' 12/16/2017 - animation for level ups and power ups.
' 12/17/2017 - small improvement to animation, power ups and the pause option.
' 12/20/2017 - improvement to animation.
' 12/20/2017 - Version 1 released.
' 1/11/2018  - Patch to the pause option: display animation instead of changing scene
' =========================================================================

INCLUDE "constants.bas"

CONST CARD_WIDTH = 8		' Width of a background card, in pixels
CONST CARD_HEIGHT = 8		' Height of a background card, in pixels

dim objectX(3), objectY(3), object(3) 'objectX keeps track of which lanes the object is using the card location, objectY keeps track of the y position for animation, object keeps track of the object in each lane
dim #objectColor(4)
' 0 = nothing
' 1 = rock
' 2 = coin
' 3 = apple (extra live)
' 4 - 6 = power up

#objectColor(0) = SPR_GREEN '^^^^ colors for object ^^^^
#objectColor(1) = SPR_GREY
#objectColor(2) = SPR_YELLOW
#objectColor(3) = SPR_RED
#objectColor(4) = SPR_BLUE
#objectColor(5) = SPR_BLACK
#objectColor(6) = SPR_GREEN


objectX(0) = 4 'range 0 - 19
objectX(1) = 7
objectX(2) = 9

for a = 0 to 2
    objectY(a) = random(3)
	object(a) = 2
next a

playerX = random(3)
#playerColor = SPR_RED 'color of character
playerDX = 1 'rate of frame change
playerY = 10 'player y  position
playerF = 2	'player first frame
invisible = 0 'activation of power ups
bonus_exp = 0
bonus_lives = 0

chance = 0 'used to determinate which object to show

'Level ajustament
dificulty = 1 'level's dificulty
#maximunScore = 100 'level's score to pass it
dim percentage(4) 'keep track of the likelihood of an object appearing

const highestDifficulty = 7 'highest dificulty possible
scene = 0
jump = 0
#score = 0
heartrate = 0 'animation for heart
lives = 3
level = 1
univclock=0

street_lineY = 0 'road lines tracking

'MODE   SCREEN_COLOR_STACK, STACK_GREEN, STACK_BLACK, STACK_GREEN, STACK_BLACK

wait
DEFINE 0,16,screen_bitmaps_0
wait
DEFINE 16,16,screen_bitmaps_1
wait
DEFINE 32,16,screen_bitmaps_2
wait
DEFINE 48,4,screen_bitmaps_3
wait
define 52,5, player
wait
define 57,2, tiles
wait
define 59,3, street
wait
define 62,1, nothing
wait
define 63,1, rock
wait
define 64,1, coin
wait
define 65,1, apple
wait

DEF FN SpritePosX(aColumn, anOffset) = ((aColumn + 1) * CARD_WIDTH ) + anOffset 'allows for the sprite to be used in a similar way to print at
DEF FN SpritePosY(aRow, anOffset) = ((aRow    + 1) * CARD_HEIGHT) + anOffset

cls
main:

	IF scene = 0 THEN GOSUB scene1 'intro
	IF scene = 1 THEN GOSUB scene2 'game
	IF scene = 2 THEN GOSUB scene3 'end
	
	univclock = (univclock + 1) % 128 'used for animation and control over how offen something show up
goto main

scene1: procedure 'Introduction
	wait
	print at SCREENPOS(1, 0) color CS_WHITE,"- RunnerZ"
	print at SCREENPOS(1, 1) color CS_WHITE,"- v1.1"
	print at SCREENPOS(1, 2) color CS_WHITE,"- Made by: Josue"
	print at SCREENPOS(1, 3) color CS_WHITE,"- Github: JosueCom"
	print at SCREENPOS(0, 10) color CS_WHITE, "'Right' to continue"
	
	if univclock%8 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'frame to show during animation
	
	SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(5, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
	
	if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," " ' right arrow animation
	
	IF cont1.right THEN scene = 1: mode 1 : gosub levelupAnimation 'go to game once pressed
	return

end

scene2: procedure
	SCREEN screen_cards 'draw background
	gosub determinelevel 'determinate properties of the current level
	gosub background 'draw extra things in the background such as score and lives
	gosub drawObjects 'draw object and determinate their properties and behavior
	gosub drawPlayer  'draw player and determinate his behavior
	'IF FRAME AND 1 THEN GOSUB move_player
	'IF FRAME AND 1 THEN GOSUB enemy
	
	if lives <= 0 then gosub clearAll : gosub clearPower : scene = 2 'if their is not more lives go to the end
	if lives > 99 then lives = 10 : invisible = 100 'if lives if greater than what the screen can show give it 10 lives and the power up invisible for a long period
	if #score >= #maximunScore then level = level + 1 : gosub clearPower : #score = 0 : gosub levelupAnimation 'if score obtained, move to the next level
	
	wait
	return
end

scene3: procedure 'End scene

	MODE   SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK
	wait

	print at SCREENPOS(2, 2) color CS_BLUE,"Made by: Josue"
	print at SCREENPOS(2, 3) color CS_WHITE,"Press 'Right' To:"
	print at SCREENPOS(2, 4) color CS_WHITE,"> Play Again"
	print at SCREENPOS(2, 5) color CS_WHITE,"Press 'Left' To:"
	print at SCREENPOS(2, 6) color CS_WHITE,"> Quit"
	if univclock%15 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1
	
	SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(7, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
	
	'play again or end the game
	if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," "
	if heartrate then print at SCREENPOS(0, 11) color CS_WHITE,"<" else print at SCREENPOS(0, 11) color CS_WHITE," "
	
	wait 'allow for time for the player to not miss press the button
	wait
	wait
	wait
	wait
	wait
	
	'reset everything with the right and game to the left
	if cont1.right then gosub clearAll : #score = 0 : lives = 3 : scene = 0 : level = 1 : wait : wait : wait : wait : wait : wait : wait : wait : wait : wait
	if cont1.left then gosub clearAll :goto end
	
end

background: procedure 'draw and writes extra details to background such as score and lives 
	if (univclock % 4) = 0 then street_lineY = (street_lineY + 1) % 7
	
	SPRITE 5, SpritePosX(4 - street_lineY/2, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR59 + SPR_GREY 'draw lines in lanes
	SPRITE 6, SpritePosX(7, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR60 + SPR_GREY
	SPRITE 7, SpritePosX(9 + street_lineY/2, 0) + VISIBLE, SpritePosY(5 + street_lineY, 0) + ZOOMY2, SPR61 + SPR_GREY
	
	gosub writescore 'write score
	gosub drawheart  'draw heart and nothing of lives
	gosub writelevel 'write the current level
	
	return
end

drawObjects: procedure
	
	for a = 0 to 2
		if (univclock % (highestDifficulty-dificulty)) = 0 then 'objects move at different rate depending on the dificulty
			objectY(a) = (objectY(a) + 1) % 8
			if objectY(a) = 0 then gosub chooseObject : object(a) = chance
		end if
		
	next a
	
	objectX(0) = 4 - objectY(0)/2
	objectX(2) = 9 + objectY(2)/2
	
	for a = 1 to 3
		if object(a - 1) >= 4 then 'if statement to see if power up has appear; draw different color for power ups
			SPRITE a, SpritePosX(objectX(a - 1), 0) + VISIBLE, SpritePosY(4 + objectY(a - 1), 0) + ZOOMY2, SPR62 + (object(a - 1) - 3)* 8 + #objectColor(object(a - 1))
			'if object(a - 1) = 4 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\319"
			'if object(a - 1) = 5 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\320"
			'if object(a - 1) = 6 then print to SCREENPOS(12 + object(a - 4), 9) color #objectColor(object(a - 1)), "\321"
		else 'if there is not power ups
			SPRITE a, SpritePosX(objectX(a - 1), 0) + VISIBLE, SpritePosY(4 + objectY(a - 1), 0) + ZOOMY2, SPR62 + object(a - 1) * 8 + #objectColor(object(a - 1))
		end if
	next a
	
	return
end

drawPlayer: procedure 'collision with the player and player's behavior
	if cont1.left AND univclock%5 = 0 then playerX = playerX - 1 'various commands: move right, move left, jump, pause
	if cont1.right AND univclock%5 = 0 then playerX = playerX + 1
	if cont1.up AND univclock%5 = 0 AND playerY = 10 then jump = 5
	if cont1.B0 AND univclock%5 = 0 then gosub pauseScene
	
	playerX = (playerX + 3) % 3 'keep player within the three lanes: 0 = lane 1, 1 = lane 2, 2 = lane 3
	
	if univclock%(highestDifficulty-dificulty) = 0 AND jump > 0 then playerY = 10 - jump + 2: jump = jump - 1 : playerF = 3 'check to see if condition for power ups and jump have been met
	if univclock%(highestDifficulty-dificulty) = 0 AND invisible > 0 then playerY = 8: invisible = invisible - 1 : playerF = 3
	if univclock%(highestDifficulty-dificulty) = 0 AND bonus_lives > 0 then gosub add_lives : bonus_lives = bonus_lives - 1
	if univclock%(highestDifficulty-dificulty) = 0 AND bonus_exp > 0 then gosub add_points : bonus_exp = bonus_exp - 1
	if univclock%(highestDifficulty-dificulty) = 0 AND jump = 0 AND invisible = 0 then playerY = 10: playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1
	
	if invisible > 0 then 'different color based on the power up
		#playerColor = SPR_BLUE
	elseif bonus_lives > 0 then
		#playerColor = SPR_GREEN
	elseif bonus_exp > 0 then
		#playerColor = SPR_BLACK
	else 
		#playerColor = SPR_RED
	end if
	
	SPRITE 0, SpritePosX(2 + 4 * playerX, 0) + VISIBLE + ZOOMX2, SpritePosY(playerY, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + #playerColor 'draw player
	
	for a = 0 to 2 'check all three lanes for collision
		if (univclock%(highestDifficulty-dificulty) = 0 AND 4 + objectY(a) = playerY AND objectX(playerX) = objectX(a) AND jump = 0)then 'detects collision with objects
			if object(a) = 1 AND invisible = 0 then lives = lives - 1 : gosub lose_points  'different behavior for various objects
			if object(a) = 2 then gosub add_points : gosub writescore
			if object(a) = 3 then gosub add_points : #score = #score + 1 : lives = lives + 1 : gosub writescore : gosub drawheart
			if object(a) = 4 then invisible = 35 : power = 4 : gosub powerupAnimation
			if object(a) = 5 then bonus_exp = 5 : power = 5 : gosub powerupAnimation
			if object(a) = 6 then gosub add_points : bonus_lives = 5 : power = 6 : gosub powerupAnimation
		end if
	
	next a
	return
end

levelupAnimation: procedure 'animation when there is increase in level
	wait
	gosub clearAll
	for a = 0 to 75
		if a%3 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
	
		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(3, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'paint player red
		
		print at (SCREENPOS(7, 5)) color CS_RED, (level%10+16)*8+6 'print which level we are going to
		print at (SCREENPOS(12, 5)) color CS_RED, (level%10+16)*8+6
		wait
		wait
		wait
	next a
	gosub clearAll
end

powerupAnimation: procedure 'animation when there is a power up
	wait
	gosub clearAll
	MODE SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK 'need in order to use print at
	wait
	for a = 0 to 75
		if a%3 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
	
		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(3, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_BLUE 'paint player blue
		
		if power = 4 then print at (SCREENPOS(7, 5)) color CS_BLUE, "\319" : print at (SCREENPOS(12, 5)) color CS_BLUE, "\319" 'print which power we obtained
		if power = 5 then print at (SCREENPOS(7, 5)) color CS_WHITE, "\320" : print at (SCREENPOS(12, 5)) color CS_WHITE, "\320"
		if power = 6 then print at (SCREENPOS(7, 5)) color CS_GREEN, "\321" : print at (SCREENPOS(12, 5)) color CS_GREEN, "\321"
		
		wait
		wait
		wait
	next a
	gosub clearAll
	mode 1 'need for SCREEN command
	wait
end

'Pause scene
pauseScene: procedure 'animation for when the game is paused
	wait
	gosub clearAll
	MODE SCREEN_COLOR_STACK, STACK_BLACK, STACK_BLACK, STACK_GREEN, STACK_BLACK 'need in order to use print at
	wait
	wait
	wait
	wait
	paused = 0
	a = 0
	while paused = 0
		print at SCREENPOS(4, 2) color CS_RED,"PAUSED"
		print at SCREENPOS(2, 3) color CS_WHITE,"Press 'Right' To:"
		print at SCREENPOS(2, 4) color CS_WHITE,"> Continue"
		print at SCREENPOS(2, 5) color CS_WHITE,"Press 'Left' To:"
		print at SCREENPOS(2, 6) color CS_WHITE,"> Quit"
		
		if a%40 = 0 then heartrate = (heartrate + 1) % 2 : playerF = playerF + playerDX : if playerF >= 4 OR playerF <= 0 then playerDX = playerDX * -1 'chance player frame
		
		SPRITE 0, SpritePosX(9, 0) + VISIBLE + ZOOMX2, SpritePosY(7, 0) + VISIBLE + ZOOMY2, SPR52 + (8)*playerF + SPR_RED 'player animation
		
		'arrows animation
		if heartrate then print at SCREENPOS(19, 11) color CS_WHITE,">" else print at SCREENPOS(19, 11) color CS_WHITE," "
		if heartrate then print at SCREENPOS(0, 11) color CS_WHITE,"<" else print at SCREENPOS(0, 11) color CS_WHITE," "
		
		if cont1.left then scene = 1 : paused = 1 : wait : wait : wait : wait : wait : wait : wait : wait : wait : wait
		if cont1.right OR cont1.B0 then paused = 1
		a = a + 1
	wend
	gosub clearAll
	mode 1 'need for SCREEN command
	wait
end

writescore: procedure 'print the current score
	if #score < 0 then #score = 0

	print at (SCREENPOS(16, 2)) color CS_RED, (#score/100%10+16)*8+6 'first digit
	print at (SCREENPOS(17, 2)) color CS_RED,(#score/10%10+16)*8+6	 'second digit
	print at (SCREENPOS(18, 2)) color CS_RED,(#score%10+16)*8+6		 'third digit

	return
end

chooseObject: procedure 'pick object to put on the list that will appear in the game
	chance = RANDOM(256) 'percentage is based of 256, not 100
	
	if chance < percentage(0) then 'nothing chances
		chance = 0
	elseif chance < percentage(1) then 'rock chances
		chance = 1
	elseif chance < percentage(2) then 'coin chances
		chance = 2
	elseif chance < percentage(3) then 'apple chances
		chance = 3
	else 
		chance = RANDOM(3) + 4 'Powerup
	end if
	
	if invisible > 0 AND a = 1 then chance = 2 'if invisible is activated, make the middle lane all gold

	return
end

drawheart: procedure 'writes the number lives left and the heart animation
	if univclock%7 = 0 then heartrate = (heartrate + 1) % 2
	if heartrate then SPRITE 4, SpritePosX(16, 0) + VISIBLE, SpritePosY(5, 0) + ZOOMY2, SPR57 + #playerColor else SPRITE 4, SpritePosX(16, 0) + VISIBLE, SpritePosY(5, 0) + ZOOMY2, SPR58 + #playerColor
	print at (SCREENPOS(17, 5)) color CS_RED,(lives/10%10+16)*8+6
	print at (SCREENPOS(18, 5)) color CS_RED,(lives%10+16)*8+6
	return
end

writelevel: procedure 'writes the level at the bottom of the screen

	print at (SCREENPOS(17, 8)) color CS_RED, (level%10+16)*8+6

	return
end

determinelevel: procedure 'percentage is out of 256; likelihood of an object appearing go to line 25-28 to see what each percentage if for from the index
	if(level = 1) then 
		dificulty=1 'rate of object showing up
		#maximunScore = 100 'score needed to pass level
		percentage(0) = 51
		percentage(1) = percentage(0) + 51
		percentage(2) = percentage(1) + 122
		percentage(3) = percentage(2) + 25
	elseif(level = 2) then 
		dificulty=1
		#maximunScore = 110
		percentage(0) = 64
		percentage(1) = percentage(0) + 64
		percentage(2) = percentage(1) + 97
		percentage(3) = percentage(2) + 25
	elseif(level = 3) then 
		dificulty=2
		#maximunScore = 130
		percentage(0) = 97
		percentage(1) = percentage(0) + 58
		percentage(2) = percentage(1) + 58
		percentage(3) = percentage(2) + 25
	elseif(level = 4) then 
		dificulty=2
		#maximunScore = 150
		percentage(0) = 120
		percentage(1) = percentage(0) + 58
		percentage(2) = percentage(1) + 58
		percentage(3) = percentage(2) + 17
	elseif(level = 5) then 
		dificulty=3
		#maximunScore = 250
		percentage(0) = 120
		percentage(1) = percentage(0) + 66
		percentage(2) = percentage(1) + 51
		percentage(3) = percentage(2) + 17
	elseif(level = 6) then 
		dificulty=3
		#maximunScore = 500
		percentage(0) = 128
		percentage(1) = percentage(0) + 76
		percentage(2) = percentage(1) + 51
		percentage(3) = percentage(2) + 17
	elseif(level = 7) then 
		dificulty=4
		#maximunScore = 650
		percentage(0) = 117
		percentage(1) = percentage(0) + 58
		percentage(2) = percentage(1) + 58
		percentage(3) = percentage(2) + 12
	elseif(level = 8) then 
		dificulty=5
		#maximunScore = 750
		percentage(0) = 79
		percentage(1) = percentage(0) + 79
		percentage(2) = percentage(1) + 79
		percentage(3) = percentage(2) + 8
	elseif(level = 9) then 
		dificulty=6
		#maximunScore = 1000
		percentage(0) = 81
		percentage(1) = percentage(0) + 84
		percentage(2) = percentage(1) + 50
		percentage(3) = percentage(2) + 4
	else
		level = 1
		lives = 10
		gosub determinelevel
	end if
end

clearAll:procedure 'clear everything on the screen
	cls
	ResetSprite(0)
	ResetSprite(1)
	ResetSprite(2)
	ResetSprite(3)
	ResetSprite(4)
	ResetSprite(5)
	ResetSprite(6)
	ResetSprite(7) 
end

clearPower:procedure 'reset powers and object shown
	invisible = 0
	jump = 0
	bonus_exp = 0
	bonus_lives = 0
	object(0) = 0
	object(1) = 0
	object(2) = 0
end

add_points:	PROCEDURE 'score gained sound effect
	#score = #score + 5
	SOUND 1,400,14
	wait
	SOUND 1,300,14
	wait
	SOUND 1,500,14
	wait
	SOUND 1,,0 ' Turn volume to zero
end

lose_points:	PROCEDURE 'score loss sound effect
	#score = #score - 15
	SOUND 1,100,14
	wait
	SOUND 1,500,14
	wait
	SOUND 1,300,14
	wait
	SOUND 1,,0 ' Turn volume to zero
end

add_lives:	PROCEDURE 'life gained sound effect
	lives = lives + 1
	SOUND 1,200,14
	wait
	SOUND 1,300,14
	wait
	SOUND 1,400,14
	wait
	SOUND 1,500,14
	wait
	SOUND 1,,0 ' Turn volume to zero
end

end:
	wait
	print at SCREENPOS(6, 5) color CS_RED, "Good Bye!"
	goto end

	'graphics
player:
	'frame 0
	BITMAP "..####.."
	BITMAP "#.####.."
	BITMAP "#.######"
	BITMAP "######.#"
	BITMAP "..####.#"
	BITMAP "..####.#"
	BITMAP "..#....."
	BITMAP "..#....."
	'frame 1
	BITMAP "..####.."
	BITMAP "..####.."
	BITMAP "#.####.."
	BITMAP "########"
	BITMAP "..####.#"
	BITMAP "..####.."
	BITMAP "..#..#.."
	BITMAP "..#....."
	'frame 2
	BITMAP "..####.."
	BITMAP "..####.."
	BITMAP "..####.."
	BITMAP "########"
	BITMAP "..####.."
	BITMAP "..####.."
	BITMAP "..#..#.."
	BITMAP "..#..#.."
	'frame 3
	BITMAP "..####.."
	BITMAP "..####.."
	BITMAP "..####.#"
	BITMAP "########"
	BITMAP "#.####.."
	BITMAP "..####.."
	BITMAP "..#..#.."
	BITMAP ".....#.."
	'frame 4
	BITMAP "..####.."
	BITMAP "..####.#"
	BITMAP "######.#"
	BITMAP "#.######"
	BITMAP "#.####.."
	BITMAP "#.####.."
	BITMAP ".....#.."
	BITMAP ".....#.."

tiles:	'heart icon
	BITMAP "........"
	BITMAP ".##.##.."
	BITMAP "#.##.##."
	BITMAP "#######."
	BITMAP ".#####.."
	BITMAP "..###..."
	BITMAP "...#...."
	BITMAP "........"
	'empty heart icon
	BITMAP "........"
	BITMAP ".##.##.."
	BITMAP "##.##.#."
	BITMAP "#.....#."
	BITMAP ".#...#.."
	BITMAP "..#.#..."
	BITMAP "...#...."
	BITMAP "........"
	
street:
	'left
	BITMAP "....##.."
	BITMAP "....##.."
	BITMAP "....##.."
	BITMAP "...###.."
	BITMAP "...##..."
	BITMAP "...##..."
	BITMAP "...##..."
	BITMAP "...##..."
	'center
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	BITMAP "##......"
	'left
	BITMAP "..##...."
	BITMAP "..##...."
	BITMAP "..##...."
	BITMAP "..##...."
	BITMAP "..###..."
	BITMAP "...##..."
	BITMAP "...##..."
	BITMAP "...##..."
	
apple:
	BITMAP ".....#.."
	BITMAP "....#..."
	BITMAP "..##.##."
	BITMAP ".#######"
	BITMAP ".#######"
	BITMAP ".#######"
	BITMAP "..#####."
	BITMAP "..##.##."

nothing:
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	BITMAP "........"
	
rock:
	BITMAP "..#####."
	BITMAP ".#.#####"
	BITMAP "####..##"
	BITMAP "####.###"
	BITMAP "########"
	BITMAP "########"
	BITMAP ".###.##."
	BITMAP "..####.."

coin:
	BITMAP "..####.."
	BITMAP ".######."
	BITMAP "########"
	BITMAP "###..###"
	BITMAP "###..###"
	BITMAP "########"
	BITMAP ".######."
	BITMAP "..####.."

	' 49 bitmaps
screen_bitmaps_0:
	DATA $FFFF,$E0FF,$E0E0,$E0E0
	DATA $FFFF,$00FF,$0000,$0000
	DATA $FFFF,$07FF,$0707,$0707
	DATA $0100,$0D07,$1F1F,$FF7F
	DATA $76E0,$BA6F,$F7CD,$FFFF
	DATA $E0E0,$E0E0,$E0E0,$E0E0
	DATA $6000,$C390,$1424,$6394
	DATA $0000,$3B00,$45C5,$3BC5
	DATA $0000,$D900,$3C24,$9D20
	DATA $0707,$0707,$0707,$0707
	DATA $E000,$4542,$4242,$FF4A
	DATA $0000,$A600,$AFA9,$47C8
	DATA $0000,$3C00,$3040,$7408
	DATA $FFFF,$FEFE,$FCFC,$F8F8
	DATA $0F00,$1F1F,$3F3F,$7F7F
	DATA $FF00,$FFFF,$FFFF,$FFFF
screen_bitmaps_1:
	DATA $FE00,$FEFE,$FEFE,$FEFE
	DATA $7F00,$7F7F,$7F7F,$BF7F
	DATA $F000,$F8F8,$FCFC,$FEFE
	DATA $0101,$0000,$0000,$0000
	DATA $FFFF,$7FFF,$3F7F,$1F1F
	DATA $F0F0,$C0E0,$80C0,$0080
	DATA $0000,$0101,$0303,$0707
	DATA $FDFD,$FDFD,$FDFD,$FBFD
	DATA $BFBF,$BFBF,$BFBF,$DFDF
	DATA $0000,$8080,$C0C0,$E0E0
	DATA $070F,$0307,$0101,$0000
	DATA $FFFF,$FFFF,$FFFF,$7FFF
	DATA $FEFF,$FCFE,$F8FC,$F0F8
	DATA $0F0F,$1F1F,$3F3F,$7F7F
	DATA $FBFB,$FBFB,$FBFB,$F7F7
	DATA $DFDF,$DFDF,$EFDF,$EFEF
screen_bitmaps_2:
	DATA $F0F0,$F8F8,$FCFC,$FEFE
	DATA $3F7F,$1F1F,$070F,$0307
	DATA $E000,$4340,$4744,$FB4C
	DATA $0000,$3400,$9595,$8819
	DATA $0C00,$C604,$E424,$EE04
	DATA $E0E0,$C0C0,$8080,$0000
	DATA $F7F7,$F7F7,$EFF7,$EFEF
	DATA $EFEF,$EFEF,$F7F7,$F7F7
	DATA $EFEF,$EFEF,$DFDF,$DFDF
	DATA $F7F7,$FBF7,$FBFB,$FBFB
	DATA $DFDF,$BFDF,$BFBF,$BFBF
	DATA $FBFB,$FDFD,$FDFD,$FDFD
	DATA $BFBF,$7F7F,$7F7F,$7F7F
	DATA $FEFD,$FEFE,$FEFE,$FEFE
	DATA $E0E0,$E0E0,$FFE0,$FFFF
	DATA $0000,$0000,$FF00,$FFFF
screen_bitmaps_3:
	DATA $0707,$0707,$FF07,$FFFF

	REM 20x12 cards
screen_cards:
	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E00,$1E08,$1E08,$1E08,$1E10
	DATA $1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1E28,$1E37,$1E3F,$1E47,$1E48
	DATA $1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1600,$1600,$1600,$1E48
	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1A1F,$1A27,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1600,$1600,$1600,$1E48
	DATA $1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1200,$1E28,$1E57,$1E5F,$1E67,$1E48
	DATA $2400,$186E,$1000,$1874,$187C,$1884,$187C,$187C,$188C,$187C,$1894,$189E,$18A6,$2400,$2400,$1E28,$1600,$1600,$1600,$1E48
	DATA $2400,$18AE,$18B4,$2000,$2000,$18BC,$2000,$2000,$18C4,$2000,$2000,$18CC,$18D6,$18DE,$2400,$1E28,$1600,$1600,$1600,$1E48
	DATA $18E6,$1000,$18EC,$2000,$2000,$18F4,$2000,$2000,$18FC,$2000,$2000,$1904,$1000,$190E,$2400,$1E28,$1F17,$1F1F,$1F27,$1E48
	DATA $192E,$18B4,$2000,$2000,$2000,$1934,$2000,$2000,$193C,$2000,$2000,$2000,$18CC,$189E,$18A6,$1E28,$1600,$1600,$1600,$1E48
	DATA $1000,$18EC,$2000,$2000,$2000,$1944,$2000,$2000,$194C,$2000,$2000,$2000,$1904,$1000,$18D6,$1E28,$1600,$1600,$1600,$1E48
	DATA $18B4,$2000,$2000,$2000,$2000,$1954,$2000,$2000,$195C,$2000,$2000,$2000,$2000,$18CC,$1000,$1E28,$1600,$1600,$1600,$1E48
	DATA $18EC,$2000,$2000,$2000,$2000,$1964,$2000,$2000,$196C,$2000,$2000,$2000,$2000,$1904,$1000,$1F70,$1F78,$1F78,$1F78,$1F80