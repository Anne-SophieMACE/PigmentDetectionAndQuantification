
// asks the user the directory to treat; should contain images, ROI created by both 
// pigment localization macro & distance to nucleus macro
dir_img = getDirectory("Choose your directory to treat");

// list all files; if TIF
filelist = getFileList(dir_img) ;
for (i_file = 0; i_file < lengthOf(filelist); i_file++) {
    if (endsWith(filelist[i_file], ".tif")) { 
    	roi_file_exists = false;
    	for (j = 0; j < lengthOf(filelist); j++) {
    		if( startsWith(filelist[j], filelist[i_file]+"_ROI_0") && endsWith(filelist[j], ".zip") ){
    			roi_file_exists = true;
    			roi_file = dir_img+File.separator+filelist[j];
    		}
    	}
    	
    	if( roi_file_exists ){
    		print("Treating "+filelist[i_file]);
    		recomputePigmentsLoc(dir_img,roi_file);
    	}
    	
    	run("Close All");
    } 
}

run("Close All");

function recomputePigmentsLoc(dir_img,file_ROI){
	// clears everything
	run("Close All");
	run("Clear Results"); 	
	run("Set Measurements...", "mean modal centroid stack redirect=None decimal=2");

		
	// resets manager
	roiManager("reset");
	roiManager("Show All");
	roiManager("Show None");
	
	
	// opens the ROI file
	roiManager("open", file_ROI);
	
	// opens the image file corresponding to the acquisiton
	orig_img = substring(file_ROI,lastIndexOf(file_ROI, File.separator)+1,indexOf(file_ROI, "_ROI_"));
	open(dir_img+orig_img);
	orig_img_name = getTitle();
	img_path = getDirectory("image");
	run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel"); // scale in pixels
	getDimensions(width, height, channels, slices, frames); // image dimensions
	
	// check if there is a "slice" information 
	str_slice = "1-"+slices;
	first_slice = 1;
	if( indexOf(file_ROI, "_slices") != -1 ){ // slice information -> substack made
		str_slice = substring(file_ROI,indexOf(file_ROI, "_slices")+lengthOf("_slices"),lastIndexOf(file_ROI, "."));
	}
	first_slice = parseInt(substring(str_slice,0,lastIndexOf(str_slice,"-")));
	// duplicates the slices
	selectWindow(orig_img_name);
	
	run("Select All");
	run("Duplicate...", "title=img_analysis duplicate slices="+str_slice);
	img_name = getTitle();
	
	// deletes the original image
	selectWindow(orig_img_name);
	close();
	
	// searches for the number of cells i.e. the number of ROIs 
	// with name starting by "ROI"
	nbROI_cell = 1;
	if( indexOf(file_ROI, "cell") != -1 ){
		roiManager("select", nbROI_cell);
		roi_name = Roi.getName();
		while( startsWith(roi_name,"ROI") ){
			nbROI_cell++;
			roiManager("select", nbROI_cell);
			roi_name = Roi.getName();
		}
	}
	
	// removing the first ROIs (= ROIs of the cells of the first macro)
	for( i_r = 0; i_r < nbROI_cell; i_r++){ 
		roiManager("select", 0);
		roiManager("delete");
	}
	
	// measurement of the spot = pigments coordinates
	roiManager("deselect");
	roiManager("measure");
	
	nbPigments = roiManager("count");
	spots_xcoord = newArray(nbPigments);
	spots_ycoord = newArray(nbPigments);
	spots_zcoord = newArray(nbPigments);
	spots_cell = newArray(nbPigments);
	
	// get coordinates of the pigment centers
	for (i_r = 0; i_r < nbPigments; i_r++) {
		// X,Y are given in pixels (because unscaled image)
		spots_xcoord[i_r] = getResult("X", i_r);
		spots_ycoord[i_r] = getResult("Y", i_r);
		// Slice is given in numero of slice
		spots_zcoord[i_r] = getResult("Slice", i_r);
	}
	
	// duplicate nuclei image to create nuclei mask image
	selectWindow(img_name);
	roiManager("show all");
	roiManager("show none");
	run("Duplicate...", "title=nucl_img duplicate channels="+channels);
	run("Z Project...", "projection=[Max Intensity]");
	z_proj_img = getTitle();
	selectWindow(z_proj_img);
	run("Select All");
	run("Duplicate...", "title=mask_nucl");
	run("Multiply...", "value=0");
	
	
	// opens the Cell & nuclei ROIs to create the mask image
	roiManager("open", img_path+File.separator+"ROIs_cell_nucleus_"+orig_img+".zip");
	nbCell = (roiManager("count") - nbPigments)/2;
	
	selectWindow("mask_nucl");
	for(i_nucl = nbPigments+nbCell; i_nucl < roiManager("count"); i_nucl++){ // 1 if nucleus
		roiManager("select", i_nucl);
		run("Add...", "value=1");
	}
	
	
	run("Clear Results");
	selectWindow("mask_nucl");
	roiManager("deselect");
	roiManager("measure");
	
	// tab loc contains "inside", "border", "outside"
	tabLocPig = newArray(nbPigments);
	for (i_pg = 0; i_pg < nbPigments; i_pg++) {
		if( getResult("Mean", i_pg) == 1 )
			tabLocPig[i_pg] = "inside";
		else{
			if( getResult("Mean", i_pg) > 0.01 )
				tabLocPig[i_pg] = "border";
			else
				tabLocPig[i_pg] = "outside";
		}
	}
	
	// creation of the cell mask image	
	selectWindow(z_proj_img);
	run("Select All");
	run("Duplicate...", "title=label_cell");
	run("Multiply...", "value=0");
	
	selectWindow("label_cell");
	for(i_nucl = nbPigments; i_nucl < nbPigments+nbCell; i_nucl++){
		roiManager("select", i_nucl);
		run("Add...", "value="+i_nucl-nbPigments+1);
	}
	run("Clear Results");
	
	selectWindow("label_cell");
	roiManager("deselect");
	roiManager("measure");
	
	for (i_pg = 0; i_pg < nbPigments; i_pg++)
		spots_cell[i_pg] = getResult("Mode", i_pg);
	
	run("Clear Results");
	for (i_pg = 0; i_pg < nbPigments; i_pg++) {
		setResult("X", i_pg, spots_xcoord[i_pg]);
		setResult("Y", i_pg, spots_ycoord[i_pg]);
		setResult("Z after slice removal", i_pg, spots_zcoord[i_pg]);
		setResult("Z original stack", i_pg, first_slice-1+spots_zcoord[i_pg]);
		setResult("Cell", i_pg, spots_cell[i_pg]);
		setResult("Loc", i_pg, tabLocPig[i_pg]);
	}
	saveAs("Results", img_path+File.separator+orig_img+"_coord_loc_eachPig.xls");

}
