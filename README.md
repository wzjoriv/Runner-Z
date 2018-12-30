# RUNNERZ--intellivision_Game
Game created for the intellivision console

To test it in a computer, an emulator is required. Intybasic SDK can be found here: http://atariage.com/forums/topic/240526-introducing-the-intybasic-sdk/. Once the SDK is installed, either go to the shortcut named "IntyBASIC SDK Command Console" inside the IntyBasic SDK folder or using command promprt, navivate to the folder holding the project. Once there, type "intyrun [name of the program]" to complile and assemble the code. This will create a rom file that can be used to play the game on an intellivision console. As mentioned before for those who do not have a console, the SDK also brings an emulator. To access it, type "jzintv [the name of the game] -p [the address of the folder 'IntyBASIC SDK\bin\roms']" and press enter. This will open an small window where the game will run.

UPDATE: Another great emulator that does not require the Command Prompt is Bliss: http://www.intellivisionworld.com/english/resources/emulators.asp. In order to run it you will need to take miniexec.bin and minigrom.bin from the "IntyBASIC SDK\bin\roms" folder mentioned above, and copy them, move them to the folder "\Bliss" and rename them to exec.bin and grom.bin. Once you are done with this, just go to the application, open it, click on "open" at the top, look for it and click on the rom file.

# Overview:

  - The game is a clasical mobile running game adapted for the this console. The character can do things such as jumping and switching lanes. One of it lastest features, it is the ability to obtain power up. The game currently only has 3: short ghostly invisibility, bonus points, bonus lives. In order to obtain them, you need to find them in the game. They look like other object but have a different color. They are also rare to find. If you find one, a back screen will appear with your character and the power up you obtain.
  
  - The game also has different stages each stage will contain more challenges to face. When you pass to a new level an black screen will appear with the level you reach.
  
# Controllers:
  - jump = up button
  - move to the right = right button
  - move to the left = left button
  - pause = pause key (not tested)

-For macs's users, I do not know of any emulator but you are welcome to look it up in the forum: http://atariage.com/forums/forum/144-intellivision-programming/.
