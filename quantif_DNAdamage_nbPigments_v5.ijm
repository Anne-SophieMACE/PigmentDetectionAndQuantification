/*
 * quantif_DNAdamage_nbPigments_v5.ijm
 * 
 * This macro computes mean intensity in nucleus 
 * and cell for several channels as well as pigments numbers. 
 * This is an update of quantif_DNAdamage_nbPigments_v3 to treat 
 * any stack with more than 2 colors; only requirement: 
 * 		last channel is cyan (dapi) = nucleus
 * 		penultimate channel is trans (brightfield) = pigment
 * 
 * If pigments one of the macro_detect_pigment_* should be launched 
 * before on the image (the zip created will be used)
 * 
 * v5: adds the possibility of a label
 * 
 * tested on 1.53c on Mac
 */

// closes all open image
run("Close All");
// asks the user the image he wants to analyze
path = File.openDialog("Choose your multi-channels image"); 

// resets manager
roiManager("reset");
roiManager("Show All");
roiManager("Show None");
run("Set Measurements...", "area mean stack redirect=None decimal=2");

// opens the image
open(path);
//gets image name and directory
img_name = getTitle();
img_path = getDirectory("image");
getDimensions(width, height, channels, slices, frames); // image dimensions

if( channels < 2 )
	exit("Your image should have at least 2 channels (BF and nucleus)");


color_chan_LUT = newArray(channels);
for (i_ch = 0; i_ch < channels; i_ch++) {
	Stack.setChannel(i_ch+1);
	color_chan_LUT[i_ch] = ""+findLUTColor();
}

// lists the content of dir_res
allFiles = getFileList(img_path); 
// look for zip file associated to the image
nb_zip = 0;
for (i_f = 0; i_f < lengthOf(allFiles); i_f++) {
	if( endsWith(allFiles[i_f],".zip") ){
		if(startsWith(allFiles[i_f], img_name)){
			nb_zip++;
		}
	}
}

// 3 possibilities: 1/ no zip: user draws cell, 0 pigements
//					2/ one zip: directly loaded
//					3/ several zip: the users chooses
zip_file = "";
if( nb_zip == 1 ){ // one zip
	for (i_f = 0; i_f < lengthOf(allFiles); i_f++) {
		if( endsWith(allFiles[i_f],".zip") ){
			if(startsWith(allFiles[i_f], img_name)){
				roiManager("open", img_path+allFiles[i_f]);
				zip_file = allFiles[i_f];
			}
		}
	}
}
else {
	if( nb_zip == 0 ){ // no zip`
		setTool("freehand");
		selectWindow(img_name); 
		waitForUser("Draw the cells (add them to Manager); no zip found (0 pigments considered)");
		for (i = 0; i < roiManager("count"); i++) {
			roiManager("select", i);
			roiManager("rename", "ROI_cell"+i+1);
		}

		roiManager("show all");
		roiManager("show none");
	}
	else{ // more than one zip
		tab_names_zip = newArray(nb_zip);

		nb_zip = 0;
		for (i_f = 0; i_f < lengthOf(allFiles); i_f++) {
			if( endsWith(allFiles[i_f],".zip") ){
				if(startsWith(allFiles[i_f], img_name)){
					tab_names_zip[nb_zip] = allFiles[i_f];
					nb_zip++;
				}
			}
		}

		Dialog.create("Title");
		Dialog.addMessage("Choose your zip (if several checked, only the last checked will be taken)");
		for (i = 0; i < nb_zip; i++) {
			Dialog.addCheckbox(tab_names_zip[i], false);
		}
		Dialog.show();

		zip_file = tab_names_zip[0];
		for (i = 0; i < nb_zip; i++) {
			if( Dialog.getCheckbox() )
				zip_file = tab_names_zip[i];
		}
		roiManager("open", img_path+zip_file);
	}
}

str_slice = "1-"+slices;
if( indexOf(zip_file, "_slices") != -1 ){ // slice information -> substack made
	str_slice = substring(zip_file,indexOf(zip_file, "_slices")+7,lastIndexOf(zip_file, "."));
}

if( nb_zip == 0 ){
	Dialog.create("Slices reduction");
	Dialog.addMessage("Enter the slices you want to study, between 1 and "+slices);
	Dialog.addNumber("First slice", 1);
	Dialog.addNumber("Last slice", slices);
	Dialog.show();
	first_slice = Dialog.getNumber();
	last_slice = Dialog.getNumber();
	str_slice = ""+first_slice+"-"+last_slice;
}

proj_img_name = performZproj(img_name,str_slice,channels);

chan_DAPI = channels;
tab_choice_quantif = newArray("No quantification","Quantification on nucleus","Quantification on cell", "Quantification on nucleus & cell");

tabQuantifEachChannel = newArray(channels);
labelChan = newArray(channels);
Dialog.create("Channel quantification");
//Dialog.addChoice("Nucleus channel", tab_chan, channels);
for (i_ch = 0; i_ch < channels; i_ch++){
	Dialog.addChoice("Quantification for channel "+i_ch+1, tab_choice_quantif);
	Dialog.addToSameRow();
	Dialog.addString("Label for the Result table",color_chan_LUT[i_ch]);
}
Dialog.show();

for (i_ch = 0; i_ch < channels; i_ch++){
	tabQuantifEachChannel[i_ch] = Dialog.getChoice();
	labelChan[i_ch] = Dialog.getString();
}

// retrieves the number of cells
cell_roi = 0;
for (i_roi = 0; i_roi < roiManager("count"); i_roi++) {
	roiManager("select", i_roi);
	name_roi = Roi.getName;
	if( startsWith(name_roi, "ROI_cell") )
		cell_roi++;
}

// retrieves the number of pigments per cell
nbPigmentsPerCell = newArray(cell_roi);
for (i_roi = 0; i_roi < roiManager("count"); i_roi++) {
	roiManager("select", i_roi);
	name_roi = Roi.getName;
	for (i_cell = 0; i_cell < cell_roi; i_cell++) {
		if( startsWith(name_roi, "Cell"+i_cell+1) ){
			nbPigmentsPerCell[i_cell] = nbPigmentsPerCell[i_cell]+1 ;
		}
	}
}

// removes pigments ROI
while( roiManager("count") != cell_roi){
	roiManager("select", roiManager("count")-1);
	roiManager("delete");
}

// create Mask image
createNucleusMask(proj_img_name,chan_DAPI);

selectWindow(proj_img_name);
run("Duplicate...", "title=Nucleus_chan duplicate channels="+channels);
run("Enhance Contrast", "saturated=0.35");

// for each cell looks for a nucleus within the ROI cell
for (i_cell = 0; i_cell < cell_roi; i_cell++) {
	selectWindow("Mask_nucleus");
	roiManager("select", i_cell);
	run("Analyze Particles...", "size=500-Infinity display add");

	selectWindow("Nucleus_chan");
	
	if( roiManager("count") != cell_roi+ i_cell +1 ){ // none or more than one nucl found
		while( roiManager("count") > cell_roi+ i_cell){
			roiManager("select", roiManager("count")-1);
			roiManager("delete");
		}
		beg_mess = "Draw";
	}
	else {
		roiManager("show none");
		roiManager("select", roiManager("count")-1);
		beg_mess = "Check";
	}
	waitForUser(beg_mess+" the nucleus of cell "+i_cell+1+" (add it to the manager, if necessary delete the wrong one)");

	roiManager("select", roiManager("count")-1);
	roiManager("rename","Nucleus_cell_"+i_cell+1);
}

selectWindow("Mask_nucleus");
close();
selectWindow("Nucleus_chan");
close();

run("Clear Results");
selectWindow(proj_img_name);
setTool("rectangle");
waitForUser("Draw a square for noise removal (ALL channels)");
run("Measure Stack...", "channels order=czt(default)");

bg_channels = newArray(channels);

for (i_ch = 0; i_ch < channels; i_ch++)
	bg_channels[i_ch] = getResult("Mean", i_ch);

tabValQuantif_raw = newArray(channels*cell_roi*2);

run("Clear Results");

selectWindow(proj_img_name);
for (i_roi = 0; i_roi < roiManager("count"); i_roi++) {
    roiManager("select", i_roi);
    run("Measure Stack...", "channels order=czt(default)");
}

// first ROI: all channels, second ROI: all channels etc.
for (i_res = 0; i_res < nResults(); i_res++)
    tabValQuantif_raw[i_res] = getResult("Mean", i_res);

run("Clear Results");
createEmptyResultsTable(); // so that the results are in the same order as in previous versions
updateResults();
for (i_cell = 0; i_cell < cell_roi; i_cell++) {
	setResult("Cell", i_cell, "Cell"+i_cell+1);
	setResult("Number of pigments", i_cell, nbPigmentsPerCell[i_cell]);

	indexBegCellTabVal = i_cell*channels;
	indexBegNuclTabVal = i_cell*channels+cell_roi*channels;
	for (i_ch = 0; i_ch < channels; i_ch++) {
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus"){
			setResult("Background value chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell,bg_channels[i_ch]);
			setResult("Mean raw value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegNuclTabVal+i_ch]);
			setResult("Final mean value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegNuclTabVal+i_ch]-bg_channels[i_ch]);
		}
		if( tabQuantifEachChannel[i_ch] == "Quantification on cell"){
			setResult("Background value chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell,bg_channels[i_ch]);
			setResult("Mean raw value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegCellTabVal+i_ch]);
			setResult("Final mean value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegCellTabVal+i_ch]-bg_channels[i_ch]);
		}
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus & cell"){
			setResult("Background value chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell,bg_channels[i_ch]);
			setResult("Mean raw value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegNuclTabVal+i_ch]);
			setResult("Final mean value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegNuclTabVal+i_ch]-bg_channels[i_ch]);

			setResult("Mean raw value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegCellTabVal+i_ch]);
			setResult("Final mean in cell chan"+i_ch+1+"("+labelChan[i_ch]+")", i_cell, tabValQuantif_raw[indexBegCellTabVal+i_ch]-bg_channels[i_ch]);
		}
	}

}
updateResults();

saveAs("Results", img_path+File.separator+"Results_"+img_name+"_DNAdamage_quantif.xls");

selectWindow(proj_img_name);
saveAs("tiff", img_path+File.separator+getTitle()+".tif");

roiManager("deselect");
roiManager("save", img_path+File.separator+"ROIs_cell_nucleus_"+img_name+".zip");

// z-proj for this set: max proj channels 1,2 and 4, min proj channel 3
function performZproj(img_stk,str_slice,nbChan){
	selectWindow(img_stk);
	run("Duplicate...", "title=forZproj duplicate slices="+str_slice);
	run("Split Channels");

	str_merge_chan = "";

	incr_ch = 1;

	for (i_ch = 0; i_ch < nbChan-2; i_ch++) {
		selectWindow("C"+i_ch+1+"-forZproj");
		run("Z Project...", "projection=[Max Intensity]");
		rename("C"+i_ch+1+"-zproj");
		selectWindow("C"+i_ch+1+"-forZproj");
		str_merge_chan = str_merge_chan+ "c"+i_ch+1+"=C"+i_ch+1+"-zproj ";
		close();
	}
	
	// BF channel 
	selectWindow("C"+nbChan-1+"-forZproj");
	run("Z Project...", "projection=[Min Intensity]");
	rename("C"+nbChan-1+"-zproj");
	selectWindow("C"+nbChan-1+"-forZproj");
	close();
	str_merge_chan = str_merge_chan+"c"+nbChan-1+"=C"+nbChan-1+"-zproj ";
	incr_ch++;
	
	// cyan channel 
	selectWindow("C"+nbChan+"-forZproj");
	run("Z Project...", "projection=[Max Intensity]");
	rename("C"+nbChan+"-zproj");
	selectWindow("C"+nbChan+"-forZproj");
	close();
	str_merge_chan = str_merge_chan+"c"+nbChan+"=C"+nbChan+"-zproj ";

	run("Merge Channels...", str_merge_chan+"create");
	rename(substring(img_stk,0,lastIndexOf(img_stk, "."))+"z_proj");

	return substring(img_stk,0,lastIndexOf(img_stk, "."))+"z_proj";
}

// computes the nucleus mask on the projection, indicated channel
function createNucleusMask(img_proj,chan_DAPI){
	selectWindow(img_proj);
	roiManager("Show All");
	roiManager("Show None");
	run("Duplicate...", "title=Mask_nucleus duplicate channels="+chan_DAPI);
	run("Subtract Background...", "rolling=500");
	run("Median...", "radius=2");
	run("Gaussian Blur...", "sigma=2");
	run("8-bit");
	run("Auto Threshold", "method=MaxEntropy white");
	run("Remove Outliers...", "radius=2 threshold=50 which=Bright");
}

// this function returns the LUT of the image IF it is one of the following
// ones: red/green/blue/magenta/gray (done by comparing the values of the LUT)
function findLUTColor(){
	color_LUT = "";
	getLut(reds, greens, blues);

	Array.getStatistics(reds, min_red, max_red, mean_red, stdDev_red);
	Array.getStatistics(greens, min_gr, max_gr, mean_gr, stdDev_gr);
	Array.getStatistics(blues, min_bl, max_bl, mean_bl, stdDev_bl);

	if( min_red == 0 && max_red == 0 && min_gr == 0 && max_gr == 0)
		color_LUT = "blue";

	if( min_red == 0 && max_red == 0 && min_bl == 0 && max_bl == 0)
		color_LUT = "green";

	if( min_bl == 0 && max_bl == 0 && min_gr == 0 && max_gr == 0)
		color_LUT = "red";

	if( min_red == 0 && max_red == 0 && mean_gr == mean_bl && stdDev_gr == stdDev_bl)
		color_LUT = "cyan";

	if( min_gr == 0 && max_gr == 0 && mean_bl == mean_red && stdDev_bl == stdDev_red)
		color_LUT = "magenta";

	if( mean_gr == mean_bl && stdDev_gr == stdDev_bl && mean_bl == mean_red && stdDev_bl == stdDev_red)
		color_LUT = "gray";

	return color_LUT;
}

function createEmptyResultsTable(){
	setResult("Cell", 0, 0);
	setResult("Number of pigments",0,0);
	
	for (i_ch = 0; i_ch < channels; i_ch++) {// !="No quantification"
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus"){
			setResult("Mean raw value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", 0, 0);
		}
		if( tabQuantifEachChannel[i_ch] == "Quantification on cell"){
			setResult("Mean raw value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
		}
		
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus & cell"){
			setResult("Mean raw value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")", 0,0);
			setResult("Mean raw value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
		}
		
	}
	for (i_ch = 0; i_ch < channels; i_ch++) {// all background values
		if( tabQuantifEachChannel[i_ch] != "No quantification" ){
			setResult("Background value chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
		}
	}
	for (i_ch = 0; i_ch < channels; i_ch++) {// !="No quantification"
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus"){
			setResult("Final mean value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
		}
		if( tabQuantifEachChannel[i_ch] == "Quantification on cell"){
			setResult("Final mean value in whole cell chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
		}
		
		if( tabQuantifEachChannel[i_ch] == "Quantification on nucleus & cell"){
			setResult("Final mean value on nucleus chan"+i_ch+1+"("+labelChan[i_ch]+")",0,0);
			setResult("Final mean in cell chan"+i_ch+1+"("+labelChan[i_ch]+")", 0,0);
		}
	}
}
