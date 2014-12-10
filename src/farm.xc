typedef unsigned char uchar;

#include <platform.h>
#include <stdio.h>
#include <timer.h>
#include "pgmIO.h"
//MUST BE MULTIPLE OF 8
#define IMHT 16
#define IMWD 16
out port cled0 = PORT_CLOCKLED_0;
out port cled1 = PORT_CLOCKLED_1;
out port cled2 = PORT_CLOCKLED_2;
out port cled3 = PORT_CLOCKLED_3;
out port cledG = PORT_CLOCKLED_SELG;
out port cledR = PORT_CLOCKLED_SELR;
in port  buttons = PORT_BUTTON;

char infname[] = "test.pgm";     //put your input image path here, absolute path
char outfname[] = "testout.pgm"; //put your output image path here, absolute path

int showLED(out port p, chanend fromVisualiser) {
    unsigned int lightUpPattern;
    while (1) {
        fromVisualiser :> lightUpPattern; //read LED pattern from visualiser process
        if (lightUpPattern == 1) break;
        p <: lightUpPattern;              //send pattern to LEDs
    }
    return 0;
}

void decimalToBinary(int output[], int decimal){
    int a = decimal;
    int i=0;
    int binaryNum[12] = {0};
    int segmentTotal = 0, currentIndex = 0;
    //build the binary number in reverse in binaryNum[]
    while(a != 0){
        binaryNum[i] = a%2;

        a = a/2;

        i++;
    }
    //build the binary number so the LED's are able to correctly choose which LED to light.
    for(i=0; i<4; i++){
        if (binaryNum[currentIndex] == 1) segmentTotal += 4;
        if (binaryNum[currentIndex+1] == 1) segmentTotal += 2;
        if (binaryNum[currentIndex+2] == 1) segmentTotal += 1;
        output[i] = segmentTotal<<4;
        segmentTotal = 0;
        currentIndex += 3;
    }
    return;
}

void visualiser(chanend fromDist,
                chanend toQuadrant0,
                chanend toQuadrant1,
                chanend toQuadrant2,
                chanend toQuadrant3)
{
    int isPaused = 0;
    int currentRound = 0;
    int totalCells = 0;
    int array[4] = {0};
    int isRed = 1;
    cledR <: isRed;
    while(1){

        fromDist :> isPaused;

        //If not paused, prepare array for dispplay with number of cells alive
        if(isPaused == 0){
            fromDist :> totalCells;
            //not enough leds
            //divide by 100 and show in green
            if (totalCells >= 4096) {
                isRed = 0;
                totalCells = totalCells/100;
                if (totalCells > 4095) totalCells = 4095;
            }
            else {
                isRed = 1;
            }
            cledR <: isRed;
            cledG <: !isRed;
            decimalToBinary(array, totalCells);
        }
        else if (isPaused == 1){
            fromDist :> currentRound;
            if (currentRound >= 4096) {
                currentRound = 4095;
            }
            decimalToBinary(array, currentRound);
            isRed = 1;
            cledR <: isRed;
            cledG <: !isRed;
        }
        //terminate
        else if(isPaused == 2){
            toQuadrant0 <: 0;
            toQuadrant1 <: 0;
            toQuadrant2 <: 0;
            toQuadrant3 <: 0;
            toQuadrant0 <: 1;
            toQuadrant1 <: 1;
            toQuadrant2 <: 1;
            toQuadrant3 <: 1;
            break;
        }
        //switch colour
        else if(isPaused == 3){
            isRed = !isRed;
            cledR <: isRed;
            cledG <: !isRed;
        }
        //Display current information on LEDs (Number of cells alive or current round)
        toQuadrant0 <: array[3];
        toQuadrant1 <: array[2];
        toQuadrant2 <: array[1];
        toQuadrant3 <: array[0];
    }
    return;
}

//takes in array of 8 uchars and converts them to be stored in one uchar
uchar convertFromBitForm(uchar line[8]){
    uchar cell = 0;
    if(line[0] == 255){
        cell++;
    }
    for(int i = 1; i < 8; i++){
        cell = cell << 1;
        if(line[i] == 255){
            cell++;
        }
    }
    return cell;
}

//takes in one uchar and converts it to an array of 8 uchars
void convertToBitForm(uchar line[8], uchar input){
    for(int i = 0; i < 8; i++){
        if ((1&(input>>(7-i)))) line[i] = 255;
        else line[i] = 0;
    }
    return;
}

void buttonListener(in port b, chanend toDataIn, chanend toDist){
    int distMessage;
    int start = 0;
    //0 means continue
    //1 means terminate
    //2 means pause
    //3 means print
    //4 means restart
    int gameState = 0;
    int r;
      while (1) {
        if (!start) printf( "Press A to begin processing the image\n");
        select {
          case b when pinsneq(15) :> r:// check if some buttons are pressed
            delay_milliseconds(150);
            //Triggers the start of image processing
            //can only be pressed when game is not started
            if(r == 14 && !start){
                start = 1;
                toDataIn <: start;
            }
            //Triggers the game to be paused
            else if(r == 13 && start){
                if (gameState == 2) {
                    gameState = 0;
                }
                else {
                    printf("Paused\n");
                    gameState = 2;
                }
            }
            //Triggers the export of the current game as a PNG file
            else if(r == 11 && start){
                //printf("print state\n");
                gameState = 3;
            }
            //Triggers the program to terminate gracefully
            else if(r == 7 && start){
                gameState = 1;
                //printf("terminate state\n");
            }
            break;
          case toDist :> distMessage:
            if (distMessage == 1){
                toDataIn <: 2;
                //printf("button terminating\n");
                return;
            }

            toDist <: gameState;
            //so we dont print every time
            if (gameState == 3) {
                gameState = 0;
            }
            //deal with pause shenanigans
            if (gameState == 2) {
                while (1){
                    b when pinsneq(15) :> r;
                    delay_milliseconds(250);
                    //unpause
                    if (r == 13) {
                        printf("Unpaused\n");
                        gameState = 0;
                        toDist <: gameState;
                        break;
                    }
                    //restart
                    else if (r == 14) {
                        printf("Restarting\n");
                        gameState = 4;
                        toDist <: gameState;
                        start = 0;
                        gameState = 0;
                        //ready to restart
                        toDist :> distMessage;
                        break;
                    }
                    //printout
                    else if (r == 11){
                        gameState = 3;
                        toDist <: gameState;
                    }
                    //terminate
                    else if (r == 7){
                        gameState = 1;
                        toDist <: gameState;
                        break;
                    }
                }
            }
            break;
        }
        //delay_milliseconds(150);
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from pgm file with path and name infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out, chanend fromButton)
{
  int res;
  int instruction = 0;
  uchar line[ IMWD ];

  while (1){
    fromButton :> instruction;
    if (instruction == 2) break;

    printf( "Reading in...\n" );
    res = _openinpgm( infname, IMWD, IMHT );
    if( res )
    {
      printf( "DataInStream:Error openening %s\n.", infname );
      return;
    }
    for( int y = 0; y < IMHT; y++ )
    {
      _readinline( line, IMWD );
      for( int x = 0; x < IMWD; x++ )
      {
        c_out <: line[ x ];
        //printf( "-%4.1d ", line[ x ] ); //uncomment to show image values
      }
      if (y%(IMHT/4) == 0){
          if (y == IMHT/4) printf("25%%\n");
          else if (y == IMHT/2) printf("50%%\n");
          if (y == 3*IMHT/4) printf("75%%\n");
      }
      //printf( "\n" ); //uncomment to show image values
    }
    _closeinpgm();
    printf( "...reading done\n" );
  }
  //printf( "DataInStream:Done...\n" );
  return;
}

//fill array for when the input is in read from pgm form
void fillArrayComplex(chanend c, uchar array[], int arraySize){
  uchar segment[8];
  if (arraySize != IMWD/8) printf("make sure arraysize is IMWD/8, crash inc\n");
  for (int i=0; i<arraySize; i++){
      for (int j=0; j<8; j++){
          c :> segment[j];
      }
      array[i] = convertFromBitForm(segment);
  }
  return;
}

void fillArray(chanend c, uchar array[], int arraySize){
  for (int i=0; i<arraySize; i++){
      c :> array[i];
  }
  return;
}

//should be able to be replaced with better pointing for speedup
void makeEqualArrays(uchar one[], uchar two[], int size){
  for(int i=0; i<size; i++){
      one[i] = two[i];
  }
  return;
}

void establishArrays(int numberOfCycles, chanend c_in, uchar above[], uchar calculate[], uchar below[]) {
  //first time leaves row above to 0s
  //and reads two lines not one
  if (numberOfCycles != 1) {
      makeEqualArrays(above,calculate,IMWD/8);
      makeEqualArrays(calculate,below,IMWD/8);
  }
  else {
      for (int i=0;i<IMWD/8;i++){
          above[i] = 0;
      }
      fillArrayComplex(c_in, calculate, IMWD/8);
  }

  //last time sets row below to 0s
  if (numberOfCycles != IMHT) {
      fillArrayComplex(c_in, below, IMWD/8);
  }
  else {
      for (int i = 0; i<IMWD/8; i++){
                below[i] = 0;
            }
  }
  return;
}

void establishArraysFromStore(int numberOfCycles, chanend c_in[], uchar above[], uchar calculate[], uchar below[]) {
  //first time leaves row above to 0s
  //and reads two lines not one
  if (numberOfCycles-1 != 1) {
      makeEqualArrays(above,calculate,IMWD/8);
      makeEqualArrays(calculate,below,IMWD/8);
  }
  else {
      for (int i=0;i<IMWD/8;i++){
          above[i] = 0;
      }
      c_in[(numberOfCycles-1)%4] <: 0;
      c_in[(numberOfCycles-1)%4] <: (numberOfCycles-1);
      fillArray(c_in[(numberOfCycles-1)%4], calculate, IMWD/8);
  }

  //last time sets row below to 0s
  if (numberOfCycles-1 != IMHT) {

      c_in[numberOfCycles%4] <: 0;
      c_in[numberOfCycles%4] <: numberOfCycles;
      fillArray(c_in[numberOfCycles%4], below, IMWD/8);
  }
  else {
      for (int i = 0; i<IMWD/8; i++){
          below[i] = 0;
      }
  }
  return;
}

void read(uchar above[], uchar calculate[], uchar below[], chanend fromDist, int cellIndex) {
  fromDist :> above[cellIndex];
  fromDist :> calculate[cellIndex];
  fromDist :> below[cellIndex];
}

int getCharIndex(int cellIndex){
  while(cellIndex%8 != 0){
      cellIndex--;
  }
  return cellIndex/8;
}

//checks 2/3 values for life, index and either side
//set isCalc to 1 to not count index
//can take any array point, it's mildly clever
uchar areAliveAroundIndex(uchar array[], int cellIndex, int charIndex, int isCalc){
  uchar output = 0;
  //the index of the bit within the char
  int localIndex = cellIndex%8;

  //end of one char, need to check ms bit of next one
  if (localIndex == 7){
      output += 1&(array[charIndex]>>(8-localIndex));
      if (charIndex != (IMWD/8-1)) {
          output += ((128&(array[charIndex+1]))>>7);
      }
  }
  //start of one char, need to check ls bit of previous one
  else if (localIndex == 0){
      output += 1&(array[charIndex]>>(6-localIndex));
      if (charIndex != 0) output += 1&(array[charIndex-1]);
  }
  else {
      //possible speedup
      if(array[charIndex] == 0) return output;
      //here we know it is safe to do this
      output += 1&(array[charIndex]>>(6-localIndex));
      output += 1&(array[charIndex]>>(8-localIndex));
  }
  //the bit itself is checked
  if (!isCalc) output += 1&(array[charIndex]>>(7-localIndex));
  return output;
}

uchar numberOfNeighbours(uchar abv[],
                         uchar cal[],
                         uchar blw[],
                         int cellIndex,
                         int charIndex) {
  uchar output = 0;

  output += areAliveAroundIndex(abv,cellIndex,charIndex,0);
  output += areAliveAroundIndex(cal,cellIndex,charIndex,1);
  output += areAliveAroundIndex(blw,cellIndex,charIndex,0);

  return output;
}

 uchar calculateCell(uchar abv[],
                    uchar cal[],
                    uchar blw[],
                    int cellIndex){
  uchar neighbours;

  //the index of the char the given bit is in
  int charIndex = getCharIndex(cellIndex);

  neighbours = numberOfNeighbours(abv,cal,blw,cellIndex,charIndex);

  //game logic
  //this just tests if the current bit is 0
  if (!(1&(cal[charIndex]>>(7-(cellIndex%8))))){
      if (neighbours == 3){
          return (uchar) 255;
      }
      else {
          return (uchar) 0;
      }
  }
  else {
      if (neighbours < 2){
          return (uchar) 0;
      }
      else if (neighbours <= 3) {
          return (uchar) 255;
      }
      else {
          return (uchar) 0;
      }
  }
}

int addUpChar(uchar input[8]){
  int output = 0;
  for (int i=0;i<8;i++){
      if (input[i] == 255) output++;
  }
  return output;
}

//code sent to worker from dist is:
//0 - no work remains
//(1-(IMHT))(1-IMWD)(0|255)+ - line number, how much to process, info
//3 -
//code sent from worker to dist is:
//1 - finished work ready for more
//code sent to worker from dist is:
//1 - about to send work
void worker(chanend fromDist, streaming chanend toHarvest) {
  int lineNumber;
  int width;
  int liveCells = 0;
  int cellIndex = 0;
  uchar above[IMWD/8];
  uchar below[IMWD/8];
  uchar calculate[IMWD/8];
  uchar working[8];

  while(1){
      fromDist <: (uchar) 1;
      fromDist :> lineNumber;

      //terminate
      if (lineNumber == 0) break;
      //do work on incoming input
      else if (lineNumber == 1){
        fromDist :> lineNumber;

        fromDist :> width;
        for (int i=0; i<width; i++){
            read(above,calculate,below,fromDist,i);
        }
        cellIndex = 0;
        toHarvest <: lineNumber;
        for (int i=0; i<width*8; i++){
            working[i%8] = calculateCell(above,calculate,below,i);
            if (i%8 == 7) {
                liveCells += addUpChar(working);
                toHarvest <: convertFromBitForm(working);
            }
        }
      }
      //else send how many cells were alive
      else if (lineNumber == 2){
          fromDist <: liveCells;
          liveCells = 0;
      }
  }

  //printf("Worker terminating\n");

  return;
}

void sendWork(chanend toWork, uchar above[], uchar calculate[], uchar below[], int lineNumber, int arraySize) {
  //"work inc"
  toWork <: 1;
  //send line number
  toWork <: lineNumber;
  //send size of blocks
  toWork <: arraySize;
  //send the three arrays
  for (int i=0; i<arraySize; i++){
      toWork <: above[i];
      toWork <: calculate[i];
      toWork <: below[i];
  }
  return;
}

void distributor(chanend c_in, chanend toWork[], chanend toStore[], chanend toHarvester, chanend fromButton, chanend toVisualiser)
{
  uchar above[IMWD/8] = {0};
  uchar below[IMWD/8];
  uchar calculate[IMWD/8];
  int readFromPgm = 1;
  int rounds = 0;
  //stores game state like paused and terminated
  int isTerminated = 0;
  int lineNumber = 1;
  int oneWorkerLive;
  int totalLive = 0;
  uchar singleWorkerStatus;

  //ARRAYS ESTABLISHED, WORKERS CAN NOW BE SENT
  //THE CALCULATION ARRAY TO COMPUTE
  //single worker status code:
  //1 - Wants work

  printf( "Image size = %dx%d\n", IMHT, IMWD );

  while(1){
    totalLive = 0;
    //printf("Current Round = %d\n", rounds);
    while(1){
      //printf("%d\n",lineNumber);
      //ESTABLISH THE ARRAYS
      if (readFromPgm == 1) {
          establishArrays(lineNumber,c_in,above,calculate,below);
      }
      else {
          establishArraysFromStore(lineNumber+1,toStore,above,calculate,below);
      }
      //work zone
      select {
        case toWork[0] :> singleWorkerStatus:
          //printf("worker[%d]\n",0);
          if (singleWorkerStatus == 1){
              sendWork(toWork[0],above,calculate,below,lineNumber,IMWD/8);
          }
          break;
        case toWork[1] :> singleWorkerStatus:
        //printf("worker[%d]\n",1);
          if (singleWorkerStatus == 1){
              sendWork(toWork[1],above,calculate,below,lineNumber,IMWD/8);
          }
          break;
        case toWork[2] :> singleWorkerStatus:
        //printf("worker[%d]\n",2);
          if (singleWorkerStatus == 1){
              sendWork(toWork[2],above,calculate,below,lineNumber,IMWD/8);
          }
          break;
        case toWork[3] :> singleWorkerStatus:
        //printf("worker[%d]\n",3);
          if (singleWorkerStatus == 1){
              sendWork(toWork[3],above,calculate,below,lineNumber,IMWD/8);
          }
          break;

      }

      //sync zone
      if (lineNumber == IMHT) {
          totalLive = 0;
          readFromPgm = 0;
          lineNumber = 1;
          //sync with harvester
          //printf("syncing...\n");
          toHarvester <: 0;
          //get live cell count
          for (int i=0;i<4;i++){
              toWork[i] :> singleWorkerStatus;
              toWork[i] <: 2;
              toWork[i] :> oneWorkerLive;
              totalLive += oneWorkerLive;
          }
          //printf("%d\n",totalLive);
          //check if user wants to terminate, print, pause or continue
          fromButton <: 0;
          fromButton :> isTerminated;
          toHarvester <: isTerminated;

          if (isTerminated == 2){
              while(1){
                  printf("Current Round = %d\n", rounds);
                  toVisualiser <: 1;
                  toVisualiser <: rounds;
                  fromButton :> isTerminated;
                  toHarvester <: isTerminated;
                  if (isTerminated == 0 || isTerminated == 1 || isTerminated == 4) {
                      break;
                  }
                  else if (isTerminated == 3) {
                      toHarvester <: 0;
                  }
              }
          }
          toVisualiser <: 0;
          toVisualiser <: totalLive;
          if (isTerminated == 4){
              uchar above[IMWD/8] = {0};
              readFromPgm = 1;
              rounds = 0;
              lineNumber = 1;
              fromButton <: 0;
          }
          //delay so data out can work
          if (isTerminated == 3){
              toHarvester <: 0;
          }
          //if (isTerminated == )
          if (isTerminated == 1){
              //tell button listener to end
              fromButton <: 1;
              toVisualiser <: 2;
          }

          //printf("done\n");
          break;
      }
      lineNumber++;
    }
    if (isTerminated == 1) break;
    else if (isTerminated == 4) {
        isTerminated = 0;
    }
    rounds++;
  }
  //terminate
  //printf("Distributer terminating\n");
  for (int i=0; i<4; i++){
      toWork[i] :> singleWorkerStatus;
      toWork[i] <: 0;
  }

  //printf( "ProcessImage:Done...\n" );
}

void sendRowToStore(int rowCalculated, streaming chanend workToHarvester[], chanend harvesterToStore[],int index) {
  uchar cellStore;
  harvesterToStore[rowCalculated%4] <: 2;
  harvesterToStore[rowCalculated%4] <: rowCalculated;
  for (int lineIndex = 0; lineIndex < IMWD/8; lineIndex++){
      workToHarvester[index] :> cellStore;
      harvesterToStore[rowCalculated%4] <: cellStore;
  }
}

void harvester(streaming chanend workToHarvester[],
               chanend harvesterToStore[],
               chanend toOut,
               chanend toDistrib,
               chanend toDataOut){
  int rowCalculated;
  int distribInstruction = 0;
  int rowsRead = 0;
  while (1) {
    select {
      case workToHarvester[0] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,0);
        break;
      case workToHarvester[1] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,1);
        break;
      case workToHarvester[2] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,2);
        break;
      case workToHarvester[3] :> rowCalculated:
        sendRowToStore(rowCalculated,workToHarvester,harvesterToStore,3);
        break;
    }
    rowsRead++;
    //sync zone
    if (rowsRead == IMWD) {
        //this channel read syncs distributor and harvester at the end of a board read
        //0 means continue
        //1 means terminate
        //3 means print
        //4 means restart
        toDistrib :> distribInstruction;
        if (distribInstruction == 0) {
            rowsRead = 0;
            for (int i=0;i<4;i++){
                harvesterToStore[i] <: 4;
            }
            //signal sync complete
            toDistrib :> distribInstruction;
            //distrib can signal termination here
        }
        if (distribInstruction == 3){
            //print
            uchar cellBlock;
            uchar converted[8];
            toDataOut <: 0;
            for (int i=1;i<=IMHT;i++){
              harvesterToStore[i%4] <: 1;
              harvesterToStore[i%4] <: i;
              for (int j=0;j<IMWD/8;j++){
                harvesterToStore[i%4] :> cellBlock;
                convertToBitForm(converted,cellBlock);
                for (int k=0;k<8;k++){
                    toOut <: converted[k];
                }
              }
            }
            toDataOut <: 0;
            toDistrib :> distribInstruction;
            //print
        }
        if (distribInstruction == 2){
            while(1){
                toDistrib :> distribInstruction;
                if (distribInstruction == 0 || distribInstruction == 1 || distribInstruction == 4) break;
                else if (distribInstruction == 3){
                    //print
                    uchar cellBlock;
                     uchar converted[8];
                     toDataOut <: 0;
                     for (int i=1;i<=IMHT;i++){
                       harvesterToStore[i%4] <: 1;
                       harvesterToStore[i%4] <: i;
                       for (int j=0;j<IMWD/8;j++){
                         harvesterToStore[i%4] :> cellBlock;
                         convertToBitForm(converted,cellBlock);
                         for (int k=0;k<8;k++){
                             toOut <: converted[k];
                         }
                       }
                     }
                    toDataOut <: 0;
                    toDistrib :> distribInstruction;
                    //print
                }
            }
        }
        if (distribInstruction == 1){
            toDataOut <: 2;
          for (int i=0;i<4;i++){
              harvesterToStore[i] <: 0;
          }
          break;
        }
        if (distribInstruction == 4){
            distribInstruction = 0;
            rowsRead = 0;
        }
    }
  }
  //printf("terminating harvester\n");
  return;
}

int hashFunction(int rowNumber){
  while (rowNumber%4 != 0) rowNumber++;
  return (rowNumber/4)-1;
}

//from distib needs to be added so we can easily cycle into another round
void store(chanend fromHarvester,chanend fromDistributor) {
  //change to make sure it always has space
  uchar store[IMHT/4][(IMWD/4)+1];
  int harvestInstruction;
  int distribInstruction;
  int rowNumber;
  int storeLocation = 0;
  while(1){
      //so instructions only activate if a message is sent from relevant control
      harvestInstruction = -1;
      distribInstruction = -1;
      select {
        case fromHarvester :> harvestInstruction:
          break;
        case fromDistributor :> distribInstruction:
          break;
      }
      //instruction from distributor
      //0 means work request
      if (distribInstruction == 0) {
          fromDistributor :> rowNumber;
          storeLocation = hashFunction(rowNumber);
          for (int j=1;j<=IMWD/8;j++){
              fromDistributor <: store[storeLocation][j];
          }
      }
      //instruction from harvester
      //0 means terminate
      //1 means harvester wants info to print out
      //2 means harvester will send info into the store
      //3 means print stored arrays
      //4 means reset store location
      else if (harvestInstruction == 4) {
          storeLocation = 0;
      }
      else if (harvestInstruction == 3) {
          for (int i=0; i<IMHT/4; i++){
              printf("%d,%d\n",i,store[i][0]);
          }
      }
      else if (harvestInstruction == 2){
          fromHarvester :> rowNumber;
          storeLocation = hashFunction(rowNumber);
          store[storeLocation][0] = (uchar) rowNumber;
          for(int i=1;i<=IMWD/8;i++){
              fromHarvester :> store[storeLocation][i];
          }

      }
      else if (harvestInstruction == 1) {
          //harvester tells the worker which row it wants
          fromHarvester :> rowNumber;
          storeLocation = hashFunction(rowNumber);
          for (int j=1;j<=IMWD/8;j++){
              fromHarvester <: store[storeLocation][j];
          }
      }
      else if (harvestInstruction == 0) break;

  }
  //printf("terminating store\n");
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to pgm image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in, chanend fromHarvester)
{
  int res;
  //0 means continue after print
  //1 means exit after print
  //2 means exit
  int harvestInstruction = 0;
  uchar line[ IMWD ];
  while (harvestInstruction == 0){
    fromHarvester :> harvestInstruction;
    if (harvestInstruction == 2){
        break;
    }
    printf( "Printing out...\n" );
    res = _openoutpgm( outfname, IMWD, IMHT );
    if( res )
    {
      printf( "DataOutStream:Error opening %s\n.", outfname );
      return;
    }
    for( int y = 0; y < IMHT; y++ )
    {
      for( int x = 0; x < IMWD; x++ )
      {
        c_in :> line[ x ];
        //printf( "-%4.1d ", line[ x ] );
      }
      //printf("\n");
      _writeoutline( line, IMWD );
      if (y%(IMHT/4) == 0){
          if (y == IMHT/4) printf("25%%\n");
          else if (y == IMHT/2) printf("50%%\n");
          else if (y == 3*IMHT/4) printf("75%%\n");
      }
    }
    printf( "...done printing\n" );
    _closeoutpgm();
    fromHarvester :> harvestInstruction;
  }

  //printf( "DataOutStream:Terminating...\n" );
  return;
}

//MAIN PROCESS defining channels, orchestrating and starting the threads
int main()
{
  chan c_inIO; //extend your channel definitions here
  chan distToWork[4];
  streaming chan workToHarvester[4];
  chan harvesterToOut, distribToHarvest;
  chan harvesterToStore[4];
  chan distribToStore[4];
  chan buttonToDataIn;
  chan buttonToDist;
  chan harvestToDataOut;
  chan distToVisualiser;
  chan quadrant0,quadrant1,quadrant2,quadrant3;
  par //extend/change this par statement
  {
    on stdcore[1]: DataInStream( infname, c_inIO, buttonToDataIn );
    on stdcore[0]: buttonListener(buttons, buttonToDataIn, buttonToDist);
    on stdcore[2]: distributor( c_inIO, distToWork,distribToStore,distribToHarvest, buttonToDist, distToVisualiser);
    on stdcore[2]: DataOutStream( outfname, harvesterToOut,harvestToDataOut );
    on stdcore[3]: harvester(workToHarvester,harvesterToStore,harvesterToOut,distribToHarvest,harvestToDataOut);
    on stdcore[0]: worker(distToWork[0],workToHarvester[0]);
    on stdcore[0]: worker(distToWork[1],workToHarvester[1]);
    on stdcore[2]: worker(distToWork[2],workToHarvester[2]);
    on stdcore[3]: worker(distToWork[3],workToHarvester[3]);
    on stdcore[0]: store(harvesterToStore[0],distribToStore[0]);
    on stdcore[1]: store(harvesterToStore[1],distribToStore[1]);
    on stdcore[2]: store(harvesterToStore[2],distribToStore[2]);
    on stdcore[3]: store(harvesterToStore[3],distribToStore[3]);
    on stdcore[0]: visualiser(distToVisualiser,quadrant0,quadrant1,quadrant2,quadrant3);
    on stdcore[0]: showLED(cled0,quadrant0);
    on stdcore[1]: showLED(cled1,quadrant1);
    on stdcore[2]: showLED(cled2,quadrant2);
    on stdcore[3]: showLED(cled3,quadrant3);
  }
  return 0;
}

