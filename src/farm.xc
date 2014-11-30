typedef unsigned char uchar;

#include <platform.h>
#include <stdio.h>
#include <timer.h>
#include "pgmIO.h"
#define IMHT 64
#define IMWD 64
out port cled0 = PORT_CLOCKLED_0;
out port cled1 = PORT_CLOCKLED_1;
out port cled2 = PORT_CLOCKLED_2;
out port cled3 = PORT_CLOCKLED_3;
out port cledG = PORT_CLOCKLED_SELG;
out port cledR = PORT_CLOCKLED_SELR;
in port  buttons = PORT_BUTTON;

char infname[] = "test.pgm";     //put your input image path here, absolute path
char outfname[] = "outputTest.pgm"; //put your output image path here, absolute path

void printArray(uchar array[], int arraysize){
  printf("[");
  for(int i=0;i<arraysize;i++){
      printf("%d,",array[i]);
  }
  printf("]\n");
}

void buttonListener(in port b, chanend toDataIn, chanend toDist){
    int distMessage;
    int start = 0;
    //0 means continue
    //1 means terminate
    //2 means pause
    //3 means print
    int gameState = 0;
    int r;
      while (1) {
        select {
          case b when pinsneq(15) :> r:// check if some buttons are pressed
            printf("button pressed\n");
            //Triggers the start of image processing
            //can only be pressed when game is not started
            if(r == 14 && !start){
                start = 1;
                toDataIn <: start;
            }
            //Triggers the game to be paused
            else if(r == 13){
                gameState = 2;
                printf("button terminating\n");
                return;

            }
            //Triggers the export of the current game as a PNG file
            else if(r == 11){
                gameState = 3;
                printf("button terminating\n");
                return;
            }
            //Triggers the program to terminate gracefully
            else if(r == 7){
                gameState = 1;
            }
            break;
          case toDist :> distMessage:
            if (distMessage == 1){
                printf("button terminating\n");
                return;
            }
            toDist <: gameState;
            break;
        }
        delay_milliseconds(250);
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

  fromButton :> instruction;

  printf( "DataInStream:Start...\n" );
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
    //printf( "\n" ); //uncomment to show image values
  }
  _closeinpgm();
  printf( "DataInStream:Done...\n" );
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
      makeEqualArrays(above,calculate,IMWD);
      makeEqualArrays(calculate,below,IMWD);
  }
  else {
      fillArray(c_in, calculate, IMWD);
  }

  //last time sets row below to 0s
  if (numberOfCycles != IMHT) {
      fillArray(c_in, below, IMWD);
  }
  else {
      uchar below[IMWD] = {0};
  }
  return;
}

void establishArraysFromStore(int numberOfCycles, chanend c_in[], uchar above[], uchar calculate[], uchar below[]) {
  //first time leaves row above to 0s
  //and reads two lines not one
  if (numberOfCycles-1 != 1) {
      makeEqualArrays(above,calculate,IMWD);
      makeEqualArrays(calculate,below,IMWD);
  }
  else {
      for (int i=0;i<IMWD;i++){
          above[i] = 0;
      }
      c_in[(numberOfCycles-1)%4] <: 0;
      c_in[(numberOfCycles-1)%4] <: (numberOfCycles-1);
      fillArray(c_in[(numberOfCycles-1)%4], calculate, IMWD);
  }

  //last time sets row below to 0s
  if (numberOfCycles-1 != IMHT) {

      c_in[numberOfCycles%4] <: 0;
      c_in[numberOfCycles%4] <: numberOfCycles;
      fillArray(c_in[numberOfCycles%4], below, IMWD);
  }
  else {
      uchar below[IMWD] = {0};
  }
  return;
}

void read(uchar above[], uchar calculate[], uchar below[], chanend fromDist, int cellIndex) {
  fromDist :> above[cellIndex];
  fromDist :> calculate[cellIndex];
  fromDist :> below[cellIndex];
}

uchar addOneIfLive(uchar count, uchar input){
  if (input == 255){
      return count+1;
  }
  return count;
}

uchar numberOfNeighbours(uchar abv[],
                         uchar cal[],
                         uchar blw[],
                         int cellIndex) {
  uchar output = 0;
  output = addOneIfLive(output,abv[cellIndex]);
  output = addOneIfLive(output,blw[cellIndex]);
  if (cellIndex != 0) {
      output = addOneIfLive(output,abv[cellIndex-1]);
      output = addOneIfLive(output,blw[cellIndex-1]);
      output = addOneIfLive(output,cal[cellIndex-1]);
  }
  if (cellIndex != IMWD-1) {
      output = addOneIfLive(output,cal[cellIndex+1]);
      output = addOneIfLive(output,abv[cellIndex+1]);
      output = addOneIfLive(output,blw[cellIndex+1]);
  }

  return output;
}

void calculateCell(uchar abv[],
                    uchar cal[],
                    uchar blw[],
                    int cellIndex,
                    streaming chanend toHarvest){
  uchar neighbours;

  neighbours = numberOfNeighbours(abv,cal,blw,cellIndex);

  //game logic
  if (cal[cellIndex] == 0){
      //printArray(cal,IMWD);
      if (neighbours == 3){
          toHarvest <: (uchar) 255;
      }
      else {
          toHarvest <: (uchar) 0;
      }
  }
  else {
      if (neighbours < 2){
          toHarvest <: (uchar) 0;
      }
      else if (neighbours <= 3) {
          toHarvest <: (uchar) 255;
      }
      else {
          toHarvest <: (uchar) 0;
      }
  }

  return;
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
  int cellIndex = 0;
  uchar above[IMWD];
  uchar below[IMWD];
  uchar calculate[IMWD];

  while(1){
      fromDist <: (uchar) 1;
      fromDist :> lineNumber;
      if (lineNumber == 0) break;
      fromDist :> width;
      for (int i=0; i<width; i++){
          read(above,calculate,below,fromDist,i);
      }
      cellIndex = 0;
      toHarvest <: lineNumber;
      for (int i=0; i<width; i++){
          calculateCell(above,calculate,below,i,toHarvest);
      }
  }

  printf("Worker terminating\n");

  return;
}

void sendWork(chanend toWork, uchar above[], uchar calculate[], uchar below[], int lineNumber, int arraySize) {
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

void distributor(chanend c_in, chanend toWork[], chanend toStore[], chanend toHarvester, chanend fromButton)
{
  uchar above[IMWD] = {0};
  uchar below[IMWD];
  uchar calculate[IMWD];
  int readFromPgm = 1;
  int rounds = 0;
  //stores game state like paused and terminated
  int isTerminated = 0;
  int lineNumber = 1;
  uchar singleWorkerStatus;

  //ARRAYS ESTABLISHED, WORKERS CAN NOW BE SENT
  //THE CALCULATION ARRAY TO COMPUTE
  //single worker status code:
  //1 - Wants work

  printf( "Image size = %dx%d\n", IMHT, IMWD );
  printf( "Press A to begin processing the image\n");

  while(1){
    while(1){
      printf("%d\n",lineNumber);
      //ESTABLISH THE ARRAYS
      if (readFromPgm == 1) establishArrays(lineNumber,c_in,above,calculate,below);
      else {
          establishArraysFromStore(lineNumber+1,toStore,above,calculate,below);
      }
      //work zone
      select {
        case toWork[0] :> singleWorkerStatus:
          //printf("worker[%d]\n",0);
          if (singleWorkerStatus == 1){
              sendWork(toWork[0],above,calculate,below,lineNumber,IMWD);
          }
          break;
        case toWork[1] :> singleWorkerStatus:
        //printf("worker[%d]\n",1);
          if (singleWorkerStatus == 1){
              sendWork(toWork[1],above,calculate,below,lineNumber,IMWD);
          }
          break;
        case toWork[2] :> singleWorkerStatus:
        //printf("worker[%d]\n",2);
          if (singleWorkerStatus == 1){
              sendWork(toWork[2],above,calculate,below,lineNumber,IMWD);
          }
          break;
        case toWork[3] :> singleWorkerStatus:
        //printf("worker[%d]\n",3);
          if (singleWorkerStatus == 1){
              sendWork(toWork[3],above,calculate,below,lineNumber,IMWD);
          }
          break;

      }

      //sync zone
      if (lineNumber == IMHT) {
          readFromPgm = 0;
          lineNumber = 1;
          //sync with harvester
          printf("syncing...\n");
          toHarvester <: 0;
          //check if user wants to terminate, print, pause or continue
          fromButton <: 0;
          fromButton :> isTerminated;
          toHarvester <: isTerminated;
          if (isTerminated == 1){
              //tell button listener to end
              fromButton <: 1;
          }
          printf("done\n");
          break;
      }
      lineNumber++;
    }
    /*if(i == 1){
        isTerminated = 1;
    }*/
    printf("Current Round = %d\n", rounds);
    if (isTerminated == 1) break;
    rounds++;
  }
  //terminate
  printf("Distributer terminating\n");
  for (int i=0; i<4; i++){
      toWork[i] :> singleWorkerStatus;
      toWork[i] <: 0;
  }

  printf( "ProcessImage:Done...\n" );
}

void sendRowToStore(int rowCalculated, streaming chanend workToHarvester[], chanend harvesterToStore[],int index) {
  uchar cellStore;
  harvesterToStore[rowCalculated%4] <: 2;
  harvesterToStore[rowCalculated%4] <: rowCalculated;
  for (int lineIndex = 0; lineIndex < IMWD; lineIndex++){
      workToHarvester[index] :> cellStore;
      harvesterToStore[rowCalculated%4] <: cellStore;
  }
}

void harvester(streaming chanend workToHarvester[], chanend harvesterToStore[], chanend toOut, chanend toDistrib){
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
    //atm this just prints and terminates after one cycle
    //this needs to be changed to be done at the distrib's instruction
    //by adding a read from distrib at the start (like in worker)
    if (rowsRead == IMWD) {
        //this channel read syncs distributor and harvester at the end of a board read
        //0 means continue
        //1 means terminate and print
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
        if (distribInstruction == 1){
          printf("printing harvest...\n");
          uchar cell;
          for (int i=1;i<=IMHT;i++){
              harvesterToStore[i%4] <: 1;
              harvesterToStore[i%4] <: i;
              for (int j=0;j<IMWD;j++){
                harvesterToStore[i%4] :> cell;
                toOut <: cell;

              }

          }
          for (int i=0;i<4;i++){
              harvesterToStore[i] <: 0;
          }
          break;
        }
    }
  }
  printf("terminating harvester\n");
  return;
}

int hashFunction(int rowNumber){
  while (rowNumber%4 != 0) rowNumber++;
  return (rowNumber/4)-1;
}

//from distib needs to be added so we can easily cycle into another round
void store(chanend fromHarvester,chanend fromDistributor) {
  //change to make sure it always has space
  uchar store[IMHT/4][IMWD+1];
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
          for (int j=1;j<=IMWD;j++){
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
          for(int i=1;i<=IMWD;i++){
              fromHarvester :> store[storeLocation][i];
          }

      }
      else if (harvestInstruction == 1) {
          //harvester tells the worker which row it wants
          fromHarvester :> rowNumber;
          storeLocation = hashFunction(rowNumber);
          for (int j=1;j<=IMWD;j++){
              fromHarvester <: store[storeLocation][j];
          }
      }
      else if (harvestInstruction == 0) break;

  }
  printf("terminating store\n");
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to pgm image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];
  //printf( "DataOutStream:Start...\n" );
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
  }
  _closeoutpgm();
  printf( "DataOutStream:Done...\n" );
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
  par //extend/change this par statement
  {
    on stdcore[1]: DataInStream( infname, c_inIO, buttonToDataIn );
    on stdcore[0]: buttonListener(buttons, buttonToDataIn, buttonToDist);
    on stdcore[0]: distributor( c_inIO, distToWork,distribToStore,distribToHarvest, buttonToDist);
    on stdcore[2]: DataOutStream( outfname, harvesterToOut );
    on stdcore[3]: harvester(workToHarvester,harvesterToStore,harvesterToOut,distribToHarvest);
    on stdcore[0]: worker(distToWork[0],workToHarvester[0]);
    on stdcore[1]: worker(distToWork[1],workToHarvester[1]);
    on stdcore[2]: worker(distToWork[2],workToHarvester[2]);
    on stdcore[3]: worker(distToWork[3],workToHarvester[3]);
    on stdcore[0]: store(harvesterToStore[0],distribToStore[0]);
    on stdcore[1]: store(harvesterToStore[1],distribToStore[1]);
    on stdcore[2]: store(harvesterToStore[2],distribToStore[2]);
    on stdcore[3]: store(harvesterToStore[3],distribToStore[3]);
  }
  //printf( "Main:Done...\n" );
  return 0;
}

