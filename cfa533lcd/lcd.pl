#!/usr/bin/perl 

use strict;
use Fcntl;
use threads;
use threads::shared;
use Thread qw(yield);
use Time::HiRes;

##############################################################################################################################################
##### GLOBAL VARIABLES
##############################################################################################################################################

# config file
my %ConfigData = ();

# pending log data
my @LogData = ();		# array that stores log data

# thread dispatch references
my %Dispatch_HandlePacket = (
	DefaultState => \&HandlePacket_DefaultState,
	Idle => \&HandlePacket_Idle,
	MenuMain => \&HandlePacket_MenuMain,
	MenuETH => \&HandlePacket_MenuETH,
	MenuIPMI => \&HandlePacket_MenuIPMI,
	MenuGateway => \&HandlePacket_MenuGateway);

my %Dispatch_RefreshDisplay = (
	DefaultState => \&RefreshDisplay_DefaultState,
	Idle => \&RefreshDisplay_Idle,
	MenuMain => \&RefreshDisplay_MenuMain,
	MenuETH => \&RefreshDisplay_MenuETH,
	MenuIPMI => \&RefreshDisplay_MenuIPMI,
	MenuGateway => \&RefreshDisplay_MenuGateway);

# adapters and info (hash references to adapters and the name of the currently selected adapter)
my %Adapters : shared;
my $CurrentAdapter : shared;

# screen state (stores the current and previously displayed lines of text)
my @DisplayLines : shared = ("", "");
my @DisplayLines_Old : shared = ("", "");

# cursor state (stores the previous and current cursor settings)
my $CursorStyle : shared = 0;
my $CursorStyle_Old : shared = -1;
my $CursorY : shared = 0;
my $CursorX : shared = 0;
my $CursorY_Old : shared = -1;
my $CursorX_Old : shared = -1;

# scroll text (for storing scrolling text calculations)
my %ScrollTextOffset : shared = ();
my %ScrollTextDelta : shared = ();

# idle status
my $TimeoutToIdleThreshold : shared = 10;
my $TimeLastAction : shared = 0;

# menu state (stores menu display and selection information)
my $CurrentScreen : shared = 'DefaultState';
my $MenuSelection : shared = 0;
my $MenuOffset : shared = 0;
my @CurrentMenu : shared = ();
my $MenuSelectionText : shared = "";

# ethernet menu (stores menu items for ethernet menu)
my @MenuETH : shared = ("Status", "IP Address", "Subnet Mask", "MAC Address");
my @MenuIPMI : shared = ("IP Address", "Subnet Mask", "Gateway", "MAC Address", "IP Source");
my @MenuGateway : shared = ("Gateway");

# adjust IP (ip menu and default info)
my $SelectIP_Enabled : shared = 0;
my $SelectIP_Format : shared = "255.255.255.255";
my $SelectIP_Value : shared = "000.000.000.000";
my $SelectIP_CursorY : shared = 0;

##############################################################################################################################################
##### BEGIN SCRIPT
##############################################################################################################################################

LOG("----- ----- ----- ----- ----- ----- ----- ----- ----- -----");
LOG("Starting Script...");

# read the configuration file
ReadConfig();

# open the log file
LOG("Initializing Log...");
open(LogFile, "+>>" . $ConfigData{"LogFile"}) || die("Failed opening $ConfigData{LogFile}");
select((select(LogFile), $|=1)[0]);
LOG("Log Initialization OK!");

# set the baud for the LCD connection 
LOG("Establishing LCD Connection... ");
SetBaud($ConfigData{"Device"}, $ConfigData{"Baud"});

# open LCD device connection
open FH, "+<" . $ConfigData{"Device"} or die("Failed connecting to $ConfigData{Device}");
binmode FH, ":raw";
LOG("LCD Connection OK!");

# configure calculated variables
LOG("Configuring Variables...");
my $RefreshDisplayRate : shared = 1 / $ConfigData{"RefreshDisplayRate"};
LOG ("RefreshDisplayRate:$RefreshDisplayRate");
LOG("Configuration OK!");

# create threads
LOG("Creating Threads... ");
my $CheckPacketsThread = new threads \&Thread_CheckPackets, &Handler_CheckPackets;
sub Handler_CheckPackets { $SIG{'KILL'} = sub { threads->exit(); }; }
my $RefreshDisplayThread = new threads \&Thread_RefreshDisplay, &Handler_RefreshDisplay;
sub Handler_RefreshDisplay { $SIG{'KILL'} = sub { threads->exit(); }; }
LOG("Thread Creation OK!");

# reset the default LCD state
SwitchToScreen_DefaultState();

# wait for threads to complete (the script waits here until program termination)
LOG("Waiting for Threads... "); 
$CheckPacketsThread->join();
$RefreshDisplayThread->join();
LOG("Thread Completion OK!");

##############################################################################################################################################
##### THREADS
##############################################################################################################################################

sub Thread_CheckPackets
{
	LOG("Starting Thread_CheckPackets...");

	while(1)
	{
		my ($inType, $inLength, @inData, $CRC) = ();
		($inType, $inLength, @inData, $CRC) = LCD_ReceivePacket();

		no strict 'refs';
		$Dispatch_HandlePacket{$CurrentScreen}->($inType, $inLength, @inData, $CRC);
	}
}

###################################

sub Thread_RefreshDisplay
{
	LOG("Starting Thread_RefreshDisplay...");

	while (1)
	{
		no strict 'refs';
		$Dispatch_RefreshDisplay{$CurrentScreen}->();
		Time::HiRes::sleep($RefreshDisplayRate);
	}
}

##############################################################################################################################################
##### DEFAULT STATE
##############################################################################################################################################

sub SwitchToScreen_DefaultState
{
	LOG("Preparing Default State...");

	LCD_SetBacklighting($ConfigData{"Display_BrightnessInit"}, $ConfigData{"Keypad_BrightnessInit"});
	LCD_SetContrast($ConfigData{"Display_ContrastInit"});
	LCD_Clear();

	$CursorStyle = 0;
	$CursorX = 0;
	$CursorY = 0;

	ModifyDisplayLine(0, 0, 16, CenterCharacters($ConfigData{"InitTitle"}, 16));
	ModifyDisplayLine(1, 0, 16, CenterCharacters($ConfigData{"InitMessage"}, 16));
	CheckDisplayChange();
	CheckCursorChange();

	LOG("Saving Default State...");
	LCD_SaveDefaultState();

	LOG("Switching to active mode...");
	SwitchToScreen_Idle();
}

###################################

sub RefreshDisplay_DefaultState {}
sub HandlePacket_DefaultState {}

##############################################################################################################################################
##### IDLE
##############################################################################################################################################

sub SwitchToScreen_Idle
{
	LCD_SetBacklighting($ConfigData{"Display_BrightnessIdle"}, $ConfigData{"Keypad_BrightnessIdle"});
	LCD_SetContrast($ConfigData{"Display_ContrastIdle"});
	LCD_Clear();
	$CurrentScreen = 'Idle';

	$SelectIP_Enabled = 0;

	$CursorStyle = 0;
	$CursorX = 0;
	$CursorY = 0;

	ResetScroll();
	ModifyDisplayLine(0, 0, 16, CenterOrScroll("CompanyName", 0, $ConfigData{"CompanyName"}, 16, "scroll", "   "));
	ModifyDisplayLine(1, 0, 16, CenterOrScroll("CompanyInfo", 0, $ConfigData{"CompanyInfo"}, 16, "scroll", "   "));
}

###################################

sub RefreshDisplay_Idle
{
	ModifyDisplayLine(0, 0, 16, CenterOrScroll("CompanyName", 1, $ConfigData{"CompanyName"}, 16, "scroll", "   "));
	ModifyDisplayLine(1, 0, 16, CenterOrScroll("CompanyInfo", 1, $ConfigData{"CompanyInfo"}, 16, "scroll", "   "));

	CheckDisplayChange();
	CheckCursorChange();
}

###################################

sub HandlePacket_Idle
{
	my ($inType, $inLength, @inData, $CRC) = @_;	# up 1/7, down 2/8, left 3/9, right 4/10, ok 5/11, cancel 6/12

	if ($inType == 128)
	{
		if (($inData[0] >= 0) && ($inData[0] <= 5))
		{
			LCD_SetBacklighting($ConfigData{"Display_Brightness"}, $ConfigData{"Keypad_Brightness"});
			LCD_SetContrast($ConfigData{"Display_Contrast"});
			SwitchToScreen_MenuMain();
		}
	}
}

##############################################################################################################################################
##### MENU -> MAIN
##############################################################################################################################################

sub SwitchToScreen_MenuMain
{
	LCD_Clear();
	$CurrentScreen = 'MenuMain';

	$TimeLastAction = Time::HiRes::time;
	$TimeoutToIdleThreshold = 10;

	$CursorStyle = 1;
	$CursorY = 0;

	$MenuSelection = 0;
	$MenuOffset = 0;

	# get updated information about the network and IPMI adapters
	$Adapters{"ipmi"} = GetAdapterInfo_IPMI();
	$Adapters{"gateway"} = GetAdapterInfo_Gateway();
	GetNetworkAdapters();

	@CurrentMenu = sort(keys(%Adapters));
	push(@CurrentMenu, "restart ethnet");

	UpdateMenuDisplay(0, 2, 0, 16, 1, ":", "scroll", "   ", 0);
}

###################################

sub RefreshDisplay_MenuMain
{
	CheckTimeoutToIdle();

	UpdateMenuDisplay(0, 2, 0, 16, 1, ":", "scroll", "   ", 1);

	CheckDisplayChange();
	CheckCursorChange();
}

###################################

sub HandlePacket_MenuMain
{
	my ($inType, $inLength, @inData, $CRC) = @_;	# up 1/7, down 2/8, left 3/9, right 4/10, ok 5/11, cancel 6/12

	if ($inType == 128)
	{
		$TimeLastAction = Time::HiRes::time;

		if ($inData[0] == 6)		# press cancel
		{
			SwitchToScreen_Idle();
		}
		elsif ($inData[0] == 1)		# press up
		{
			UpdateMenuDisplay(1, 2, 0, 16, 1, ":", "scroll", "   ", 0);
		}
		elsif ($inData[0] == 2)		# press down
		{
			UpdateMenuDisplay(2, 2, 0, 16, 1, ":", "scroll", "   ", 0);
		}
		elsif ($inData[0] == 5)		# press ok
		{
			if ($CurrentMenu[$MenuSelection] eq "restart ethnet")
			{
				SetAdapterInfo("restart ethnet");
				SwitchToScreen_MenuMain();
			}
			elsif ($CurrentMenu[$MenuSelection] eq "ipmi")
			{
				SwitchToScreen_MenuIPMI();
			}
			elsif ($CurrentMenu[$MenuSelection] eq "gateway")
			{
				SwitchToScreen_MenuGateway();
			}
			else
			{
				SwitchToScreen_MenuETH($CurrentMenu[$MenuSelection]);
			}
		}
	}
}

##############################################################################################################################################
##### MENU -> ETH
##############################################################################################################################################

sub SwitchToScreen_MenuETH
{
	LCD_Clear();
	$CurrentScreen = 'MenuETH';

	$TimeLastAction = Time::HiRes::time;
	$TimeoutToIdleThreshold = 60;

	$CursorStyle = 1;
	$CursorY = 0;

	$MenuSelection = 0;
	$MenuOffset = 0;

	# get updated information about the network adapters
	GetNetworkAdapters();

	$CurrentAdapter = shift;
	@CurrentMenu = @MenuETH;

	my $AdapterNameLength = length($CurrentAdapter);
	$MenuSelectionText = GetValueForSelection_ETH();

	ResetScroll();
	ModifyDisplayLine(0, 0, 16, $CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
	ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoEth", 0, $MenuSelectionText, 16, "scroll", "   "));
}

###################################

sub RefreshDisplay_MenuETH
{
	CheckTimeoutToIdle();

	my $AdapterNameLength = length($CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 1);

	if ($SelectIP_Enabled == 1)
	{
		ModifyDisplayLine(1, 0, 16, $SelectIP_Value);
	}
	else
	{
		ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoEth", 1, $MenuSelectionText, 16, "scroll", "   "));
	}

	CheckDisplayChange();
	CheckCursorChange();
}

###################################

sub HandlePacket_MenuETH
{
	my ($inType, $inLength, @inData, $CRC) = @_;	# up 1/7, down 2/8, left 3/9, right 4/10, ok 5/11, cancel 6/12

	if ($inType == 128)
	{
		$TimeLastAction = Time::HiRes::time;
		my $AdapterNameLength = length($CurrentAdapter);

		if ($SelectIP_Enabled == 1)
		{
			my $Result  = SelectIP($inData[0]);

			if ($Result != 0)
			{
				if ($MenuSelection == 1) { $Adapters{$CurrentAdapter}{'IP'} = $Result; }
				elsif ($MenuSelection == 2) { $Adapters{$CurrentAdapter}{'Mask'} = $Result; }

				SetAdapterInfo("eth");
				GetNetworkAdapters();
				$MenuSelectionText = GetValueForSelection_ETH();
			}
		}
		elsif ($inData[0] == 6)		# press cancel
		{
			SwitchToScreen_MenuMain();
		}
		elsif ($inData[0] == 1)		# press up
		{
			UpdateMenuDisplay(1, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_ETH();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoEth", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 2)		# press down
		{
			UpdateMenuDisplay(2, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_ETH();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoEth", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 5)		# press ok
		{
			$MenuSelectionText = GetValueForSelection_ETH();
			if ($MenuSelection == 1) { SelectIP_Begin("IP", $MenuSelectionText); }
			elsif ($MenuSelection == 2) { SelectIP_Begin("Mask", $MenuSelectionText); }
		}
	}
}

###################################

sub GetValueForSelection_ETH
{
	if ($MenuSelection == 0) { return $Adapters{$CurrentAdapter}{'Status'}; }
	elsif ($MenuSelection == 1) { return $Adapters{$CurrentAdapter}{'IP'}; }
	elsif ($MenuSelection == 2) { return $Adapters{$CurrentAdapter}{'Mask'}; }
	elsif ($MenuSelection == 3) { return $Adapters{$CurrentAdapter}{'MAC'}; }

	return "";
}

##############################################################################################################################################
##### MENU -> IPMI
##############################################################################################################################################

sub SwitchToScreen_MenuIPMI
{
	LCD_Clear();
	$CurrentScreen = 'MenuIPMI';

	$TimeLastAction = Time::HiRes::time;
	$TimeoutToIdleThreshold = 60;

	$CursorStyle = 1;
	$CursorY = 0;

	$MenuSelection = 0;
	$MenuOffset = 0;

	# get updated information about the ipmi
	$Adapters{"ipmi"} = GetAdapterInfo_IPMI();

	$CurrentAdapter = "ipmi";
	@CurrentMenu = @MenuIPMI;

	my $AdapterNameLength = length($CurrentAdapter);
	$MenuSelectionText = GetValueForSelection_IPMI();

	ResetScroll();
	ModifyDisplayLine(0, 0, 16, $CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
	ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoIPMI", 0, $MenuSelectionText, 16, "scroll", "   "));
}

###################################

sub RefreshDisplay_MenuIPMI
{
	CheckTimeoutToIdle();

	my $AdapterNameLength = length($CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 1);

	if ($SelectIP_Enabled == 1)
	{
		ModifyDisplayLine(1, 0, 16, $SelectIP_Value);
	}
	else
	{
		ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoIPMI", 1, $MenuSelectionText, 16, "scroll", "   "));
	}

	CheckDisplayChange();
	CheckCursorChange();
}

###################################

sub HandlePacket_MenuIPMI
{
	my ($inType, $inLength, @inData, $CRC) = @_;	# up 1/7, down 2/8, left 3/9, right 4/10, ok 5/11, cancel 6/12

	if ($inType == 128)
	{
		$TimeLastAction = Time::HiRes::time;
		my $AdapterNameLength = length($CurrentAdapter);

		if ($SelectIP_Enabled == 1)
		{
			my $Result  = SelectIP($inData[0]);

			if ($Result != 0)
			{
				if ($MenuSelection == 0) { $Adapters{'ipmi'}{'IP'} = $Result; }
				elsif ($MenuSelection == 1) { $Adapters{'ipmi'}{'Mask'} = $Result; }
				elsif ($MenuSelection == 2) { $Adapters{'ipmi'}{'Gateway'} = $Result; }

				ResetScroll("InfoIPMI");
				$MenuSelectionText = "Updating: Please Wait...";
				$CursorStyle = 0;

				SetAdapterInfo("ipmi");
				$Adapters{"ipmi"} = GetAdapterInfo_IPMI();

				ResetScroll("InfoIPMI");
				$MenuSelectionText = GetValueForSelection_IPMI();
				$CursorStyle = 1;
			}
		}
		elsif ($inData[0] == 6)		# press cancel
		{
			SwitchToScreen_MenuMain();
		}
		elsif ($inData[0] == 1)		# press up
		{
			UpdateMenuDisplay(1, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_IPMI();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoIPMI", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 2)		# press down
		{
			UpdateMenuDisplay(2, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_IPMI();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoIPMI", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 5)		# press ok
		{
			$MenuSelectionText = GetValueForSelection_IPMI();
			if ($MenuSelection == 0) { SelectIP_Begin("IP", $MenuSelectionText); }
			elsif ($MenuSelection == 1) { SelectIP_Begin("Mask", $MenuSelectionText); }
			elsif ($MenuSelection == 2) { SelectIP_Begin("Gateway", $MenuSelectionText); }
		}
	}
}

###################################

sub GetValueForSelection_IPMI
{
	if ($MenuSelection == 0) { return $Adapters{$CurrentAdapter}{'IP'}; }
	elsif ($MenuSelection == 1) { return $Adapters{$CurrentAdapter}{'Mask'}; }
	elsif ($MenuSelection == 2) { return $Adapters{$CurrentAdapter}{'Gateway'}; }
	elsif ($MenuSelection == 3) { return $Adapters{$CurrentAdapter}{'MAC'}; }
	elsif ($MenuSelection == 4) { return $Adapters{$CurrentAdapter}{'Source'}; }

	return "";
}

##############################################################################################################################################
##### MENU -> Gateway
##############################################################################################################################################

sub SwitchToScreen_MenuGateway
{
	LCD_Clear();
	$CurrentScreen = 'MenuGateway';

	$TimeLastAction = Time::HiRes::time;
	$TimeoutToIdleThreshold = 60;

	$CursorStyle = 1;
	$CursorY = 0;

	$MenuSelection = 0;
	$MenuOffset = 0;

	# get updated information about the Gateway
	$Adapters{"gateway"} = GetAdapterInfo_Gateway();

	$CurrentAdapter = "gateway";
	@CurrentMenu = @MenuGateway;

	my $AdapterNameLength = length($CurrentAdapter);
	$MenuSelectionText = GetValueForSelection_Gateway();

	ResetScroll();
	ModifyDisplayLine(0, 0, 16, $CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
	ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoGateway", 0, $MenuSelectionText, 16, "scroll", "   "));
}

###################################

sub RefreshDisplay_MenuGateway
{
	CheckTimeoutToIdle();

	my $AdapterNameLength = length($CurrentAdapter);
	UpdateMenuDisplay(0, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 1);

	if ($SelectIP_Enabled == 1)
	{
		ModifyDisplayLine(1, 0, 16, $SelectIP_Value);
	}
	else
	{
		ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoGateway", 1, $MenuSelectionText, 16, "scroll", "   "));
	}

	CheckDisplayChange();
	CheckCursorChange();
}

###################################

sub HandlePacket_MenuGateway
{
	my ($inType, $inLength, @inData, $CRC) = @_;	# up 1/7, down 2/8, left 3/9, right 4/10, ok 5/11, cancel 6/12

	if ($inType == 128)
	{
		$TimeLastAction = Time::HiRes::time;
		my $AdapterNameLength = length($CurrentAdapter);

		if ($SelectIP_Enabled == 1)
		{
			my $Result  = SelectIP($inData[0]);

			if ($Result != 0)
			{
				if ($MenuSelection == 0) { $Adapters{'gateway'}{'Gateway'} = $Result; }

				ResetScroll("InfoGateway");
				$MenuSelectionText = "Updating: Please Wait...";
				$CursorStyle = 0;

				SetAdapterInfo("gateway");
				$Adapters{"gateway"} = GetAdapterInfo_Gateway();

				ResetScroll("InfoGateway");
				$MenuSelectionText = GetValueForSelection_Gateway();
				$CursorStyle = 1;
			}
		}
		elsif ($inData[0] == 6)		# press cancel
		{
			SwitchToScreen_MenuMain();
		}
		elsif ($inData[0] == 1)		# press up
		{
			UpdateMenuDisplay(1, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_Gateway();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoGateway", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 2)		# press down
		{
			UpdateMenuDisplay(2, 0, $AdapterNameLength, (16 - $AdapterNameLength), 0, ":", "scroll", "   ", 0);
			$MenuSelectionText = GetValueForSelection_Gateway();
			ModifyDisplayLine(1, 0, 16, CenterOrScroll("InfoGateway", 0, $MenuSelectionText, 16, "scroll", "   "));
		}
		elsif ($inData[0] == 5)		# press ok
		{
			$MenuSelectionText = GetValueForSelection_Gateway();
			if ($MenuSelection == 0) { SelectIP_Begin("Gateway", $MenuSelectionText); }
		}
	}
}

###################################

sub GetValueForSelection_Gateway
{
	if ($MenuSelection == 0) { return $Adapters{'gateway'}{'Gateway'}; }

	return "";
}

##############################################################################################################################################
##### Select IP
##############################################################################################################################################

sub SelectIP_Begin
{
	$SelectIP_Enabled = 1;

	$SelectIP_CursorY = $CursorY;
	$CursorY = 1;
	$CursorX = 0;

	my $inType = shift;
	$SelectIP_Value = shift;

	$SelectIP_Format = ($inType eq "IP") ? "223.255.255.255" : "255.255.255.255";
}

###################################

sub SelectIP
{
	my $inKey = shift;
	my $Value;
	my $ValueMod;
	my $newX;

	if ($inKey == 1)			# press up
	{
		$Value = substr($SelectIP_Value, $CursorX, 1);
		$ValueMod = ($Value < 9) ? ($Value + 1) : 0;
		$ValueMod = (($ValueMod > 2) && (($CursorX == 0) || ($CursorX == 4) || ($CursorX == 8) || ($CursorX == 12))) ? 0 : $ValueMod;
		substr($SelectIP_Value, $CursorX, 1) = $ValueMod;
	}
	elsif ($inKey == 2)			# press down
	{
		$Value = substr($SelectIP_Value, $CursorX, 1);
		$ValueMod = ($Value > 0) ? ($Value - 1) : 9;
		$ValueMod = (($ValueMod > 2) && (($CursorX == 0) || ($CursorX == 4) || ($CursorX == 8) || ($CursorX == 12))) ? 2 : $ValueMod;
		substr($SelectIP_Value, $CursorX, 1) = $ValueMod;
	}
	elsif ($inKey == 3)			# press left
	{
		$newX = $CursorX - 1;
		$newX -= ((($newX == 3) || ($newX == 7) || ($newX == 11)) ? 1 : 0);
		$CursorX = ($newX < 0) ? 14 : $newX;
	}
	elsif ($inKey == 4)		# press right
	{
		$newX = $CursorX + 1;
		$newX += ((($newX == 3) || ($newX == 7) || ($newX == 11)) ? 1 : 0);
		$CursorX = ($newX > 14) ? 0 : $newX;
	}
	elsif ($inKey == 5)		# press ok
	{
		for (my $ByteIndex=0; $ByteIndex<4; $ByteIndex++)
		{
			my $ByteValue = substr($SelectIP_Value, ($ByteIndex * 4), 3);
			my $ByteFormat = substr($SelectIP_Format, ($ByteIndex * 4), 3);
		}

		$SelectIP_Enabled = 0;
		$CursorY = $SelectIP_CursorY;
		return $SelectIP_Value;
	}
	elsif ($inKey == 6)		# press cancel
	{
		$SelectIP_Enabled = 0;
		$CursorY = $SelectIP_CursorY;
	}

	return 0;
}

##############################################################################################################################################
##### LOGIC HELPER FUNCTIONS
##############################################################################################################################################

sub CheckCursorChange
{
	if ($CursorStyle != $CursorStyle_Old)
	{
		LCD_SetCursorStyle($CursorStyle);
		$CursorStyle_Old = $CursorStyle;
	}

	if (($CursorY != $CursorY_Old) || ($CursorX != $CursorX_Old))
	{
		LCD_SetCursorPosition($CursorY, $CursorX);
		$CursorY_Old = $CursorY;
		$CursorX_Old = $CursorX;
	}
}

###################################

sub CheckDisplayChange
{
	if ($DisplayLines[0] ne $DisplayLines_Old[0])
	{
		LCD_DisplayData(0, 0, $DisplayLines[0]);
		$DisplayLines_Old[0] = $DisplayLines[0];
	}

	if ($DisplayLines[1] ne $DisplayLines_Old[1])
	{
		LCD_DisplayData(1, 0, $DisplayLines[1]);
		$DisplayLines_Old[1] = $DisplayLines[1];
	}
}

###################################

sub ModifyDisplayLine #($inRow, $inColumn, $inCutLength, $inCharacters)
{
	my ($inRow, $inColumn, $inCutLength, $inCharacters) = @_;

	if (($inColumn < 0) || ($inColumn > 16) || ($inRow < 0) || ($inRow > 1))
	{
		return;
	}

	$inCharacters = sprintf("%-" . $inCutLength . "s", $inCharacters);

	$DisplayLines[$inRow] = sprintf("%-16s", $DisplayLines[$inRow]);				# ensure displaylines is at least 16 characters
	substr($DisplayLines[$inRow], $inColumn, $inCutLength) = $inCharacters;
	$DisplayLines[$inRow] = substr($DisplayLines[$inRow], 0, 16);
}

###################################

sub CheckTimeoutToIdle
{
	if ((Time::HiRes::time - $TimeLastAction) >= $TimeoutToIdleThreshold)
	{
		SwitchToScreen_Idle();
		return;
	}
}

###################################

sub CenterCharacters
{
	my ($inCharacters, $inSpace) = @_;

	my $Length = length($inCharacters);

	if ($Length < $inSpace)
	{
		my $Difference = $inSpace - $Length;		# how many extra spaces there are
		my $PaddingFront = int($Difference / 2);	# extra space / 2, rounded down

		substr($inCharacters, 0, 0) = sprintf("%" . $PaddingFront . "s", "");	# pad the front of the character string
		$inCharacters = sprintf("%-16s", $inCharacters);	# increase the size / pad the back
	}

	return $inCharacters;
}

###################################

sub CenterOrScroll
{
	my ($inScrollID, $inRefresh, $inText, $inSpace, $inScrollStyle, $inSeparator) = @_;

	if (length($inText) > $inSpace)
	{
		return ScrollText($inScrollID, $inRefresh, $inText, $inSpace, $inScrollStyle, $inSeparator);
	}
	else
	{
		return CenterCharacters($inText, $inSpace);
	}
}

###################################

sub LeftOrScroll
{
	my ($inScrollID, $inRefresh, $inText, $inSpace, $inScrollStyle, $inSeparator) = @_;

	if (length($inText) > $inSpace)
	{
		return ScrollText($inScrollID, $inRefresh, $inText, $inSpace, $inScrollStyle, $inSeparator);
	}
	else
	{
		return sprintf("%-" . $inSpace . "s", $inText);	# increase the size / pad the back
	}
}

##############################################################################################################################################
##### SCROLLING TEXT
##############################################################################################################################################

sub ScrollText
{
	my ($inScrollID, $inRefresh, $inText, $inSpace, $inScrollStyle, $inSeparator) = @_;

	#$inScrollID = ID to identify scroll offset variable
	#$inText = text to display
	#$inSpace = amount of space to work in
	#$inScrollStyle = "scroll", "bounce"
	#$inSeparator = characters to put between instances of the text string

	$ScrollTextDelta{$inScrollID} = defined($ScrollTextDelta{$inScrollID}) ? $ScrollTextDelta{$inScrollID} : 1;
	my $Delta = $inRefresh * $ConfigData{"TextScrollRate"} * $RefreshDisplayRate * $ScrollTextDelta{$inScrollID};

	$ScrollTextOffset{$inScrollID} = defined($ScrollTextOffset{$inScrollID}) ? $ScrollTextOffset{$inScrollID} : -$Delta;
	my $Offset = $ScrollTextOffset{$inScrollID};

	$Offset += $Delta;

	chomp($inText);
	my $ScrollText = $inText;
	my $MaxNecessaryStringLength = length($inText);

	if ($inScrollStyle eq "scroll")
	{
		$MaxNecessaryStringLength += length($inSeparator);

		do
		{
			$ScrollText .= $inSeparator;
			$ScrollText .= $inText;
		}
		while (length($ScrollText) < $MaxNecessaryStringLength + $inSpace);

		$ScrollText = substr($ScrollText, 0, $MaxNecessaryStringLength + $inSpace);

		if ($Offset >= $MaxNecessaryStringLength)
		{
			$Offset -= $MaxNecessaryStringLength;
		}
	}
	elsif ($inScrollStyle eq "bounce")
	{
		my $BouncePadding = (($inSpace - $MaxNecessaryStringLength) > 0) ? ($inSpace - $MaxNecessaryStringLength) : 0; 
		my $BounceMaxOffset = (($MaxNecessaryStringLength - $inSpace) > 0) ? ($MaxNecessaryStringLength - $inSpace) : $BouncePadding;

		$ScrollText = (" " x $BouncePadding) . $ScrollText . (" " x $BouncePadding);

		if ($Offset < abs($Delta))
		{
			$Offset = abs($Delta);
			$ScrollTextDelta{$inScrollID} = 1;
		}
		elsif ($Offset >= ($BounceMaxOffset + 1))
		{
			$Offset = $BounceMaxOffset;
			$ScrollTextDelta{$inScrollID} = -1;
		}
	}

	$ScrollTextOffset{$inScrollID} = $Offset;
	my $ClippedText = substr($ScrollText, $Offset, $inSpace);
	return $ClippedText;
}

###################################

sub ResetScroll
{
	my $inScrollID = shift;

	if (!defined($inScrollID))
	{
		undef %ScrollTextDelta;
		undef %ScrollTextOffset;
	}
	elsif ($inScrollID eq "Menu_")
	{
		foreach my $Key (keys %ScrollTextOffset)
		{
			if (index($Key, "Menu_") == 0)
			{
				delete $ScrollTextDelta{$Key};
				delete $ScrollTextOffset{$Key};
			}
		}
	}
	else
	{
		delete $ScrollTextDelta{$inScrollID};
		delete $ScrollTextOffset{$inScrollID};	
	}

	return;
}

##############################################################################################################################################
##### MENU
##############################################################################################################################################

sub UpdateMenuDisplay
{
	my ($inY, $inRows, $inColumn, $inSpace, $inDisplayIndex, $inLegendSeparator, $inOverflow, $inOverflowSeparator, $inOverflowRefresh) = @_;
	my $MenuLength = @CurrentMenu;

	if ($inY != 0)
	{
		ResetScroll("Menu_");
	}

	if ($inY == 1) # press up
	{
		$MenuSelection -= ($MenuSelection > 0) ? 1 : 0;

		if ($inRows == 2)
		{
			$MenuOffset -= (($CursorY == 0) && ($MenuOffset > 0)) ? 1 : 0;
			$CursorY = 0;
		}

		if (($inRows == 0) || ($inRows == 1))
		{
			$CursorY = $inRows;
			$MenuOffset -= ($MenuOffset > 0) ? 1 : 0;
		}
	}
	elsif ($inY == 2) # press down
	{
		$MenuSelection += ($MenuSelection < ($MenuLength - 1)) ? 1 : 0;

		if ($inRows == 2)
		{
			$MenuOffset += (($CursorY == 1) && ($MenuOffset < ($MenuLength - 2))) ? 1 : 0;
			$CursorY = ($MenuLength > 1) ? 1 : 0;
		}

		if (($inRows == 0) || ($inRows == 1))
		{
			$CursorY = $inRows;
			$MenuOffset += ($MenuOffset < ($MenuLength - 1)) ? 1 : 0;	
		}
	}

	# determine the longest menu offset string (length of highest index number)
	# pad the shorter numbers and offset the cursor so that everything aligns
	my $IndexLength = length($MenuLength);
	my $IndexString = ($inDisplayIndex == 1) ? sprintf("%" . $IndexLength . "s", $MenuOffset + 1) : "";
	$IndexString .= $inLegendSeparator;

	if ($SelectIP_Enabled == 0)
	{
		$CursorX = $inColumn + length($IndexString) - length($inLegendSeparator);
	}

	# top row
	my $MenuString = $CurrentMenu[$MenuOffset];
	my $MenuStringSpace = $inSpace - length($IndexString);
	my $ScrollID = "Menu_$MenuOffset";
	my $DisplayString = $IndexString . LeftOrScroll($ScrollID, $inOverflowRefresh, $MenuString, $MenuStringSpace, $inOverflow, $inOverflowSeparator);

	if (($inRows == 0) || ($inRows == 2))
	{
		ModifyDisplayLine(0, $inColumn, $inSpace, $DisplayString);
	}
	elsif ($inRows == 1)
	{
		ModifyDisplayLine(1, $inColumn, $inSpace, $DisplayString);
	}

	# bottom row
	if ($inRows == 2)
	{
		my $MenuOffset1 = $MenuOffset + 1;
		$MenuString = (exists($CurrentMenu[$MenuOffset + 1])) ? $CurrentMenu[$MenuOffset + 1] : "";
		my $IndexString = ($inDisplayIndex == 1) ? sprintf("%" . $IndexLength . "s", $MenuOffset + 2) : "";
		$IndexString .= $inLegendSeparator;

		$ScrollID = "Menu_$MenuOffset1";
		$DisplayString = $IndexString . LeftOrScroll($ScrollID, $inOverflowRefresh, $MenuString, $MenuStringSpace, $inOverflow, $inOverflowSeparator);

		ModifyDisplayLine(1, $inColumn, $inSpace, $DisplayString);
	}
}

##############################################################################################################################################
##### LCD FUNCTIONS
##############################################################################################################################################

sub LCD_Clear
{
	LCD_SendPacket(0x06);
	$CursorX_Old = -1;
	$CursorY_Old = -1;
	$CursorStyle_Old = -1;
	@DisplayLines = ("", "");
	@DisplayLines_Old = ("", "");
	Time::HiRes::usleep(25000);
}

###################################

sub LCD_DisplayData
{
	my ($inRow, $inColumn, $inData) = @_;
	LCD_SendPacket(0x1F, $inColumn, $inRow, ASCII_To_Data($inData));
}

###################################

sub LCD_SetCursorPosition
{
	my ($inRow, $inColumn) = @_;
	LCD_SendPacket(0x0B, $inColumn, $inRow);
}

###################################

sub LCD_SetCursorStyle
{
	my $inStyle = shift;	# 0 = no cursor, 1 = blinking block, 2 = underscore, 3 = blinking underscore
	LCD_SendPacket(0x0C, $inStyle);
}

###################################

sub LCD_SetBacklighting
{
	my ($inLCD, $inKeypad) = @_;
	$inLCD = ($inLCD < 0) ? 0 : $inLCD;
	$inLCD = ($inLCD > 100) ? 100 : $inLCD;
	$inKeypad = ($inKeypad < 0) ? 0 : $inKeypad;
	$inKeypad = ($inKeypad > 100) ? 100 : $inKeypad;
	my @Data = ($inLCD, $inKeypad);

	LCD_SendPacket(0x0E, @Data);
	Time::HiRes::usleep(125000);
}

###################################

sub LCD_SetContrast
{
	my $inContrast = shift;
	$inContrast = ($inContrast < 0) ? 0 : $inContrast;
	$inContrast = ($inContrast > 200) ? 200 : $inContrast;

	LCD_SendPacket(0x0D, $inContrast);
	Time::HiRes::usleep(125000);
}

###################################

sub LCD_SaveDefaultState
{
	LCD_SendPacket(0x04);
	Time::HiRes::usleep(125000);
}


##############################################################################################################################################
##### RAW LCD FUNCTIONS
##############################################################################################################################################

sub LCD_SendPacket
{
	my ($inType, @inData) = @_;
	my $DataLength = scalar @inData;
	my $JoinedPacketData = join(",", @inData);
	my $CRC = pack("S", Compute_CRC($inType, @inData));
	my $Packet = pack("C*", $inType, $DataLength, @inData) . $CRC;
	syswrite(FH, $Packet);
}

###################################

sub LCD_ReceivePacket
{
	my $inStream;

	sysread(FH, $inStream, 1);
	my $PacketType = unpack("C", $inStream);

	sysread(FH, $inStream, 1);
	my $PacketLength = unpack("C", $inStream);

	my @PacketData = ();
	for (my $i = 0; $i < $PacketLength; $i++)
	{
		sysread(FH, $inStream, 1);
		$inStream = unpack("C", $inStream);
		push(@PacketData, $inStream); 
	}
	my $JoinedPacketData = join(",", @PacketData);

	my @CRC = ();
	sysread(FH, $inStream, 1);
	push(@CRC, $inStream);
	sysread(FH, $inStream, 1);
	push(@CRC, $inStream);
	my $CRC = pack("S", @CRC);
	my $JoinedCRC = join(",", @CRC);

	return ($PacketType, $PacketLength, @PacketData, $CRC);
}

###################################

sub Compute_CRC
{
	# A CRC that injects length of @inData after the type.
	# This is not a completely generic CRC, careful reusing it!

	my ($inType, @inData) = @_;
	my @CRC_LOOKUP = (
	0x00000,0x01189,0x02312,0x0329B,0x04624,0x057AD,0x06536,0x074BF,
	0x08C48,0x09DC1,0x0AF5A,0x0BED3,0x0CA6C,0x0DBE5,0x0E97E,0x0F8F7,
	0x01081,0x00108,0x03393,0x0221A,0x056A5,0x0472C,0x075B7,0x0643E,
	0x09CC9,0x08D40,0x0BFDB,0x0AE52,0x0DAED,0x0CB64,0x0F9FF,0x0E876,
	0x02102,0x0308B,0x00210,0x01399,0x06726,0x076AF,0x04434,0x055BD,
	0x0AD4A,0x0BCC3,0x08E58,0x09FD1,0x0EB6E,0x0FAE7,0x0C87C,0x0D9F5,
	0x03183,0x0200A,0x01291,0x00318,0x077A7,0x0662E,0x054B5,0x0453C,
	0x0BDCB,0x0AC42,0x09ED9,0x08F50,0x0FBEF,0x0EA66,0x0D8FD,0x0C974,
	0x04204,0x0538D,0x06116,0x0709F,0x00420,0x015A9,0x02732,0x036BB,
	0x0CE4C,0x0DFC5,0x0ED5E,0x0FCD7,0x08868,0x099E1,0x0AB7A,0x0BAF3,
	0x05285,0x0430C,0x07197,0x0601E,0x014A1,0x00528,0x037B3,0x0263A,
	0x0DECD,0x0CF44,0x0FDDF,0x0EC56,0x098E9,0x08960,0x0BBFB,0x0AA72,
	0x06306,0x0728F,0x04014,0x0519D,0x02522,0x034AB,0x00630,0x017B9,
	0x0EF4E,0x0FEC7,0x0CC5C,0x0DDD5,0x0A96A,0x0B8E3,0x08A78,0x09BF1,
	0x07387,0x0620E,0x05095,0x0411C,0x035A3,0x0242A,0x016B1,0x00738,
	0x0FFCF,0x0EE46,0x0DCDD,0x0CD54,0x0B9EB,0x0A862,0x09AF9,0x08B70,
	0x08408,0x09581,0x0A71A,0x0B693,0x0C22C,0x0D3A5,0x0E13E,0x0F0B7,
	0x00840,0x019C9,0x02B52,0x03ADB,0x04E64,0x05FED,0x06D76,0x07CFF,
	0x09489,0x08500,0x0B79B,0x0A612,0x0D2AD,0x0C324,0x0F1BF,0x0E036,
	0x018C1,0x00948,0x03BD3,0x02A5A,0x05EE5,0x04F6C,0x07DF7,0x06C7E,
	0x0A50A,0x0B483,0x08618,0x09791,0x0E32E,0x0F2A7,0x0C03C,0x0D1B5,
	0x02942,0x038CB,0x00A50,0x01BD9,0x06F66,0x07EEF,0x04C74,0x05DFD,
	0x0B58B,0x0A402,0x09699,0x08710,0x0F3AF,0x0E226,0x0D0BD,0x0C134,
	0x039C3,0x0284A,0x01AD1,0x00B58,0x07FE7,0x06E6E,0x05CF5,0x04D7C,
	0x0C60C,0x0D785,0x0E51E,0x0F497,0x08028,0x091A1,0x0A33A,0x0B2B3,
	0x04A44,0x05BCD,0x06956,0x078DF,0x00C60,0x01DE9,0x02F72,0x03EFB,
	0x0D68D,0x0C704,0x0F59F,0x0E416,0x090A9,0x08120,0x0B3BB,0x0A232,
	0x05AC5,0x04B4C,0x079D7,0x0685E,0x01CE1,0x00D68,0x03FF3,0x02E7A,
	0x0E70E,0x0F687,0x0C41C,0x0D595,0x0A12A,0x0B0A3,0x08238,0x093B1,
	0x06B46,0x07ACF,0x04854,0x059DD,0x02D62,0x03CEB,0x00E70,0x01FF9,
	0x0F78F,0x0E606,0x0D49D,0x0C514,0x0B1AB,0x0A022,0x092B9,0x08330,
	0x07BC7,0x06A4E,0x058D5,0x0495C,0x03DE3,0x02C6A,0x01EF1,0x00F78);

	my $DataLength = scalar @inData;
	my $Packet = pack("C*", $inType, $DataLength, @inData);
	my $CRC = 0xFFFF;

	foreach my $Byte (unpack('C*', $Packet))
	{
		$CRC = ($CRC >> 8) ^ $CRC_LOOKUP[($CRC ^ $Byte) & 0xFF];
	}

	$CRC = ($CRC & 0xFFFF);
	return ~$CRC;
}

###################################

sub SetBaud
{
	my ($inDevice, $inRate) = @_;

	LOG("Setting [$inDevice] to [$inRate] baud...");

	# Configure device using stty...
	system("stty $inRate -echo -echoe -echok -echoctl -echoke -parodd -ignpar -inpck -istrip raw -parmrk -parenb cs8 -cstopb < $inDevice") 
	and die "Failed to initialize [$inDevice] at rate [$inRate]!";
}

###################################

sub ASCII_To_Data
{
	my $inString = shift;
	return map {ord($_)} split(//, $inString);
}

##############################################################################################################################################
##### LOGGING
##############################################################################################################################################

sub LOG
{
	my $inText = shift;
	chomp($inText);

	my $inLogToConsole = shift;
	$inLogToConsole = defined($inLogToConsole) ? 1 : 0;

	#if ($inLogToConsole == 1)
	#{
		print ($inText . "\n");
	#}

	push(@LogData, $inText);

	if (fileno(LogFile) > 0)
	{
		while (defined(my $LogItem = shift(@LogData)))
		{
			print LogFile ($LogItem . "\n");
			Magic();
		}
	}
}

###################################

sub Magic()
{
	``;
}

##############################################################################################################################################
##### CONFIG FILE
##############################################################################################################################################

sub ReadConfig
{
	LOG("Reading Config...");

	open(CONF, "</opt/cfa533lcd/lcd.cfg") || LOG("Failed opening lcd.cfg!", 1) && exit -1;

	$ConfigData{"LogFile"} = "/var/log/lcd.log";

	$ConfigData{"Device"} = "/dev/ttyUSB0";
	$ConfigData{"Baud"} = 19200;

	$ConfigData{"InitTitle"} = "Initializing";
	$ConfigData{"InitMessage"} = "Please Wait...";

	$ConfigData{"CompanyName"} = "Zixi";
	$ConfigData{"CompanyInfo"} = "Default Information";

	$ConfigData{"RefreshDisplayRate"} = 8;
	$ConfigData{"TextScrollRate"} = 3;

	$ConfigData{"Display_Brightness"} = 100;
	$ConfigData{"Display_Contrast"} = 15;
	$ConfigData{"Keypad_Brightness"} = 100;

	$ConfigData{"Display_BrightnessIdle"} = 100;
	$ConfigData{"Display_ContrastIdle"} = 15;
	$ConfigData{"Keypad_BrightnessIdle"} = 100;

	$ConfigData{"Display_BrightnessInit"} = 50;
	$ConfigData{"Display_ContrastInit"} = 15;
	$ConfigData{"Keypad_BrightnessInit"} = 0;

	while(<CONF>)
	{
		my $InputLine = $_;
		chomp($InputLine);
		$InputLine =~ s/\R//g;

		# check if it starts with a # and ignore it as a comment
		if (index($InputLine, "#") == 0)
		{
			next;
		}

		# find the first instance of = and use that as the key/value delimiter
		my $Index = index($InputLine, "=");

		# if it was not found or was the first character...
		if ($Index < 1)
		{
			if ($InputLine != "")
			{
				LOG("Invalid Config Entry: $InputLine", 1);
			}

			next;
		}

		my $Key = substr($InputLine, 0, $Index);
		my $Value = substr($InputLine, $Index + 1);

		$ConfigData{$Key} = $Value;
		LOG("Config: $Key=$Value");
	}

	close(CONF);
}

##############################################################################################################################################
##### SET VALUES
##############################################################################################################################################

sub SetAdapterInfo()
{
	my $inType = shift;

	if ($inType eq "restart ethnet")
	{
		my $Command = "service network restart";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		return;
	}
	elsif ($inType eq "ipmi")
	{
		my $IPMI_IP = StripLeadingZeros($Adapters{'ipmi'}{'IP'});
		my $IPMI_Mask = StripLeadingZeros($Adapters{'ipmi'}{'Mask'});
		my $IPMI_Gateway = StripLeadingZeros($Adapters{'ipmi'}{'Gateway'});

		my $Command = "ipmitool lan set 1 ipaddr $IPMI_IP";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		my $Command = "ipmitool lan set 1 netmask $IPMI_Mask";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		my $Command = "ipmitool lan set 1 defgw ipaddr $IPMI_Gateway";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		return;
	}
	elsif ($inType eq "gateway")
	{
		my $Gateway = StripLeadingZeros($Adapters{'gateway'}{'Gateway'});

		foreach my $AdapterName (keys %Adapters)
		{
			my $AdapterHashRef = $Adapters{$AdapterName};
			my %AdapterHash = %$AdapterHashRef;

			if (exists($AdapterHash{'Type'}) && ($AdapterHash{'Type'} eq "Ethernet"))
			{
				my $Command = "/opt/cfa533lcd/readwriteconfig -w /etc/sysconfig/network-scripts/ifcfg-$AdapterName GATEWAY=$Gateway";
				LOG("Executing: $Command");
				my $Result = `$Command`;
				LOG(($Result eq "C") ? "Ok!" : "Error");
			}
		}

		my $Command = "route del default";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		my $Command = "ip route add default via $Gateway";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG("Result: $Result");

		return;
	}
	elsif ($inType eq "eth")
	{
		my $Eth_IP = StripLeadingZeros($Adapters{$CurrentAdapter}{'IP'});
		my $Eth_Mask = StripLeadingZeros($Adapters{$CurrentAdapter}{'Mask'});

		my $Command = "/sbin/ifconfig $CurrentAdapter $Eth_IP netmask $Eth_Mask";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		#LOG("Result: $Result");

		my $Command = "/opt/cfa533lcd/readwriteconfig -w /etc/sysconfig/network-scripts/ifcfg-$CurrentAdapter IPADDR=$Eth_IP";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG(($Result eq "C") ? "Ok!" : "Error"); 
		#LOG("Result: $Result");

		my $Command = "/opt/cfa533lcd/readwriteconfig -w /etc/sysconfig/network-scripts/ifcfg-$CurrentAdapter NETMASK=$Eth_Mask";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG(($Result eq "C") ? "Ok!" : "Error");
		#LOG("Result: $Result");

		my $Command = "/opt/cfa533lcd/readwriteconfig -w /etc/sysconfig/network-scripts/ifcfg-$CurrentAdapter ONBOOT=yes";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG(($Result eq "C") ? "Ok!" : "Error"); 

		my $Command = "/opt/cfa533lcd/readwriteconfig -w /etc/sysconfig/network-scripts/ifcfg-$CurrentAdapter BOOTPROTO=none";
		LOG("Executing: $Command");
		my $Result = `$Command`;
		LOG(($Result eq "C") ? "Ok!" : "Error"); 

		return;
	}

	LOG("Unknown type($inType) call to SetAdapterInfo!");
}

##############################################################################################################################################
##### READ VALUES
##############################################################################################################################################

sub GetNetworkAdapters
{
	#my @Adapters = `ip -o link show | awk -F" " '{print \$2 "," \$9 "," \$12 "," \$13}'`;

	my @Adapters = `ls /sys/class/net | awk -v RS=" " '{print}'`; # amit
	my $Length = @Adapters;

	my %AdapterInfo : shared;

	for (my $i=0; $i<$Length; $i++)
	{
		#my @Split = split(',', $Adapters[$i]);
		#my $Split = @Split; 

		#if (($Split != 4) || ($Split[2] ne "link/ether"))
		$Adapters[$i] =~ s/^\s+|\s+$//g; # amit
		if (($Adapters[$i] eq "lo") || ($Adapters[$i] eq "")) # amit
		{
			next;
		}

		my $AdapterName = $Adapters[$i]; #substr($Split[0], 0, -1);
		$Adapters{$AdapterName} = GetAdapterInfo_Ethernet($AdapterName);
	}
}

###################################

sub GetAdapterInfo_Ethernet
{
	my $AdapterName = shift;
	my %AdapterInfo : shared;

	# get type and mac
	# my $Link = `/sbin/ifconfig $AdapterName | grep "Link " |  awk -F" " '{print \$3 "," \$5}'`;
	# chomp($Link);
	# my @Split = split(',', $Link);
	# my $Split = @Split;

	#if ($Split != 2) { next; }

	# $AdapterInfo{'Type'} = substr($Split[0], 6);
    my $linktype = `cat /sys/class/net/$AdapterName/type`;
    my $linktype_s = "";
    chomp($linktype);
    if ( $linktype == 1 ) {
        # See http://lxr.linux.no/linux+v3.0/include/linux/if_arp.h#L30 for all possible Link Types
        $linktype_s = "Ethernet";
    } else {
        $linktype_s = "Unknown";
    }
    $AdapterInfo{'Type'} = $linktype_s;
	# $AdapterInfo{'MAC'} = FormatMAC($Split[1]);
    $AdapterInfo{'MAC'} = `cat /sys/class/net/$AdapterName/address`;

	# status
	# my $Status = `/sbin/ifconfig $AdapterName | grep "RUNNING" | awk -F" " '{print \$3}'`;
    my $Status = `cat /sys/class/net/$AdapterName/operstate`;
	chomp($Status);
	$AdapterInfo{'Status'} = ($Status eq "up") ? "Online" : "Offline";

	# ip address and mask
	my $Address = `/sbin/ifconfig $AdapterName | grep "inet " | head -1 | awk -F" " '{print \$2 "," \$4}'`;
	chomp($Address);
	my @Split = split(',', $Address);
	$AdapterInfo{'IP'} = FormatIP(($Address ne "") ? $Split[0] : "000.000.000.000");
    $AdapterInfo{'Mask'} = FormatIP(($Address ne "") ? $Split[1] : "000.000.000.000");
	sort(%AdapterInfo);
	return \%AdapterInfo;
}

###################################

sub GetAdapterInfo_IPMI
{
	my %AdapterInfo : shared;

	# address source
	my $Source = `ipmitool lan print 1 | grep -w "IP Address Source" | awk -F": " '{print \$2}'`;
	chomp($Source);
	$AdapterInfo{'Source'} = $Source;

	# get mac
	my $MAC = `ipmitool lan print 1 | grep -w "MAC Address" | awk -F": " '{print \$2}'`;
	chomp($MAC);
	$AdapterInfo{'MAC'} = FormatMAC($MAC);

	# get ip
	my $IP = `ipmitool lan print 1 | grep -w "IP Address  " | awk -F": " '{print \$2}'`;
	chomp($IP);
	$AdapterInfo{'IP'} = FormatIP($IP);

	# mask
	my $Mask = `ipmitool lan print 1 | grep -w "Subnet Mask" | awk -F": " '{print \$2}'`;
	chomp($Mask);
	$AdapterInfo{'Mask'} = FormatIP($Mask);

	# default gateway
	my $Gateway = `ipmitool lan print 1 | grep -w "Default Gateway IP" | awk -F": " '{print \$2}'`;
	chomp($Gateway);
	$AdapterInfo{'Gateway'} = FormatIP($Gateway);

	sort(%AdapterInfo);
	return \%AdapterInfo;
}

###################################

sub GetAdapterInfo_Gateway
{
	my %AdapterInfo : shared;

	# route
	my $Route = `ip route | grep default | awk -F" " '{print \$3}'`;
	chomp($Route);
	$AdapterInfo{'Gateway'} = FormatIP($Route);

	return \%AdapterInfo;
}

##############################################################################################################################################
##### FORMATTING UTILITY FUNCTIONS
##############################################################################################################################################

sub FormatMAC
{
	my $inMAC = shift;
	my @Segments = split(/:/, $inMAC);
	my $Segments = @Segments;

	if ($Segments == 6)
	{
		return "$Segments[0]$Segments[1].$Segments[2]$Segments[3].$Segments[4]$Segments[5]";
	}

	return "Invalid MAC";
}

###################################

sub FormatIP
{
	my $inIP = shift;
	my @Segments = split(/\./, $inIP);
	my $Segments = @Segments;

	if ($Segments == 4)
	{
		return sprintf("%03d.%03d.%03d.%03d", $Segments[0], $Segments[1], $Segments[2], $Segments[3]);
	}

	return "000.000.000.000";
}

###################################

sub StripLeadingZeros
{
	my $inIP = shift;

	my @Segments = split(/\./, $inIP);
	my $Segments = @Segments;

	if ($Segments == 4)
	{
		# add zero to treat this as a number which removes leading zeros
		$Segments[0] += 0;
		$Segments[1] += 0;
		$Segments[2] += 0;
		$Segments[3] += 0;

		return sprintf("%d.%d.%d.%d", $Segments[0], $Segments[1], $Segments[2], $Segments[3]);
	}

	return "0.0.0.0";
}

###################################

sub LogAdapters
{
	LOG("LogAdapters -----");

	foreach my $AdapterName (keys %Adapters)
	{
		my $AdapterHashRef = $Adapters{$AdapterName};
		my %AdapterHash = %$AdapterHashRef;
		LOG("AdapterName: $AdapterName,	AdapterHashRef: $AdapterHashRef");

		foreach my $AdapterProperty (keys %AdapterHash)
		{
			my $PropertyValue = $AdapterHash{$AdapterProperty};
			LOG("	AdapterProperty: $AdapterProperty	=	$PropertyValue");
		}
	}

	LOG("LogAdapters -----");
	return;
}

##############################################################################################################################################
##### END
##############################################################################################################################################
