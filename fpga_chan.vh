//	Parameter register addresses
// par array
localparam PAR_MTMASK = 	0;		// master trigger mask
localparam PAR_STMASK = 	1; 		// selftrigger mask
localparam PAR_SUMASK = 	2;  	// summ mask
localparam PAR_INVMASK = 	3; 		// mask for waveform inversion
localparam PAR_MTTHR = 		4; 		// data send threshold - master trigger zero suppression
localparam PAR_STTHR = 		5; 		// self trigger threshold
localparam PAR_SUTHR = 		6; 		// 64-channels sum trigger threshold (main trigger)
localparam PAR_STPRC = 		7;		// selftrigger prescale
localparam PAR_WINLEN = 	8; 		// window length for both triggers and trigger history
localparam PAR_MTWINBEG = 	9;		// master trigger window begin
localparam PAR_STWINBEG = 	10; 	// self trigger window begin
localparam PAR_SUWINBEG = 	11; 	// trigger history window begin
localparam PAR_SUDELAY =	12;		// delay of local sum for adding to other X's
localparam PAR_MTZBEG =		13;		// begin of zero suppression sensitive window, relative to MTWINBEG
localparam PAR_MTZEND =		14;		// end of zero suppression sensitive window, relative to MTWINBEG

// par array 1
localparam PAR_DTMASK = 	16;	// double channel trigger mask for channel pairs
localparam PAR_DTITHR = 	17; 	// double channel trigger : individual channel threshold
localparam PAR_DTSTHR = 	18; 	// double channel trigger : sum threshold
