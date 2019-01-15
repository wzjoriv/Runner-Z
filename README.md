# Runner-Z -- Intellivision Game
Runner-Z is a video game created for the Intellivision console of 1979. It was develop using BASIC and the intellivision compiler Intybasic. The game consist of the classical genre of games where a player runs while avoiding various obstacles as he/she does. The game allows for functions such as jumping and quickly changing lanes to avoid that obstacles. One of its lastest features, it is the ability to obtain power up; ghostly invisibility, bonus points and bonus lives. In order to obtain them, they must be acquired during the short period of time that they appear in the game. They look like other objects but have unique attributes. One can proceed throught the levels by acquiring the coins need to move on to the next level but be warm each level increases in difficulty that I challenge you pass level 8 of the game.

## Getting Started
The following are instructions to run the project for development or testing purposes. See deployment if you would only like to play the game.

### Prerequisites
To test or contribute changes to the software, the
```
Intybasic compiler and SDK
```
is neeeded. This can be download from the following link: [SDK](http://atariage.com/forums/topic/240526-introducing-the-intybasic-sdk/)

Another tool that is useful to have is a good BASIC text editor. I had issued finding one, but I though notepad++ had the best performance.

### Installing
Once you have the Intybasic SDK downloaded, download the Runner-Z project from github and move it into the Projects folder inside of the SDK.
Open the command promp inside the runnerZ folder. Then, run the compiler
``` 
intybasic runnerZ.bas asm/runnerZ.asm ../../lib
```
This will produce an ASM file that needs to go through the assembler to produce the bin and rom file that can be used to run the game
```
as1600 -o bin/runnerZ asm/runnerZ.asm
```
Lastly, open the jzintv intillivision emulator with the following command
```
jzintv bin/runnerZ -p ../../bin/roms
```

## Deployment
To run the game, an intillivision console emulator is needed. [Bliss](http://www.intellivisionbrasil.com.br/Menu_Emuladores.htm) is a popular options due to the fact that it has a GUI.
Now that you have an emaulator, open the rom file of the game inside the rom folder of the project via the emulator. 

### Keys to play the game:
  - jump = up button
  - move to the right = right button
  - move to the left = left button
  - pause = pause key

## Built With
* [Intybasic](http://atariage.com/forums/forum/144-intellivision-programming/) - used to compile the game
## Contributing
Everyone is welcome to contribute to the game. I want to see that you can do with it.
## Author
* **Josue N Rivera** - Computer Science Student at the University of Massachusetts Dartmouth
## License
This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details

## Acknowledgments
* My professor Clinton Rogers
* [The Intellivision programming community](http://atariage.com/forums/forum/144-intellivision-programming/)
