// This file is part of OpenCollar.
// Copyright (c) 2008 - 2016 Nandana Singh, Lulu Pink, Garvin Twine,    
// Joy Stipe, Cleo Collins, Satomi Ahn, Master Starship, Toy Wylie,    
// Kaori Gray, Sei Lisa, Wendy Starfall, littlemousy, Romka Swallowtail,  
// Sumi Perl, Karo Weirsider, Kurt Burleigh, Marissa Mistwallow et al.   
// Licensed under the GPLv2.  See LICENSE for full details. 
string g_sScriptVersion = "8.0";
integer LINK_CMD_DEBUG=1999;

#include "MasterFile.lsl"

string g_sParentMenu = "Main";
string g_sSubMenu = "Leash";

integer g_iVerbosity=1;
key g_kLeashedTo;

Dialog(key kID, string sPrompt, list lChoices, list lUtilityButtons, integer iPage, integer iAuth, string sName) {
    key kMenuID = llGenerateKey();
    llMessageLinked(LINK_SET, DIALOG, (string)kID + "|" + sPrompt + "|" + (string)iPage + "|" + llDumpList2String(lChoices, "`") + "|" + llDumpList2String(lUtilityButtons, "`") + "|" + (string)iAuth, kMenuID);

    integer iIndex = llListFindList(g_lMenuIDs, [kID]);
    if (~iIndex) g_lMenuIDs = llListReplaceList(g_lMenuIDs, [kID, kMenuID, sName], iIndex, iIndex + g_iMenuStride - 1);
    else g_lMenuIDs += [kID, kMenuID, sName];
}

Menu(key kID, integer iAuth) {
    string sPrompt = "\n[OpenCollar Leash]";
    list lButtons = [ "Length", "Yank", "Give Holder", "Configure", "Tie", "Pass", "Follow"];
    if(g_iLeashed)lButtons += ["Unleash"];
    else lButtons += ["Grab"];
    Dialog(kID, sPrompt, lButtons, [UPMENU], 0, iAuth, "Menu~Main");
}

ConfigMenu(key kID, integer iAuth)
{
    string sPrompt = "\n[OpenCollar Leash Config]\n\nCurrent Texture: "+g_sParticleTexture;
    list lButtons = [Checkbox((g_sParticleMode=="Ribbon"), "Ribbon"), Checkbox(g_iTurnMode, "Turn"), Checkbox((g_sParticleTexture=="Silk"), "Silk"), Checkbox((g_sParticleTexture=="Chain"), "Chain"), Checkbox((g_sParticleTexture=="Leather"),"Leather"), Checkbox((g_sParticleTexture=="Rope"),"Rope"), Checkbox(g_iNoLeash, "Invisible"), Checkbox(g_iParticleGlow, "Glow")];
    Dialog(kID, sPrompt, lButtons, ["Color", "* GRAVITY", "* SIZE", UPMENU], 0, iAuth, "Menu~Config");
}

string UnCheckbox(string sBox)
{
    // Return only the checkbox label
    integer index = llSubStringIndex(sBox," ");
    return llGetSubString(sBox,index+1,-1);
}

integer g_iNoLeash=FALSE;
integer g_iLeashed = FALSE;
integer g_iLeashedAuth = 0;
integer g_iLeashTarget;
integer g_iAlreadyMoving=FALSE;
float g_fLength = 3;
integer g_iLeasherInRange;
integer g_iFollowMode;
integer g_iJustMoved;
integer g_iAwayCounter=-1;


UserCommand(integer iNum, string sStr, key kID) {
    if(!(iNum&(C_OWNER|C_TRUSTED|C_WEARER|C_GROUP|C_PUBLIC)))return; // This example plugin limits menu and command access to owner, trusted, and wearer
    if (iNum & C_COLLAR_INTERNALS && llToLower(sStr) == "runaway") {
        g_lOwner=[];
        g_lTrust=[];
        g_lBlock=[];
        return;
    }
    if (llToLower(sStr)==llToLower(g_sSubMenu) || llToLower(sStr) == "menu "+llToLower(g_sSubMenu)) Menu(kID, iNum);
    //else if (iNum!=CMD_OWNER && iNum!=CMD_TRUSTED && kID!=g_kWearer) RelayNotify(kID,"Access denied!",0);
    else {
        //integer iWSuccess = 0; 
        string sChangetype = llToLower(llList2String(llParseString2List(sStr, [" "], []),0));
        string sChangevalue = llList2String(llParseString2List(sStr, [" "], []),1);
        //string sText;
        /// [prefix] g_sSubMenu sChangetype sChangevalue
        if(g_iVerbosity>=3){
            llRegionSayTo(kID, 0, "Leash commandline: "+sStr);
        }
        if(sChangetype == "unleash")
        {
            if(MaskOutranks(iNum, g_iLeashedAuth)){
                if(g_iLeashed){
                    llStopMoveToTarget();
                    g_iLeashed=FALSE;
                    g_iAlreadyMoving=FALSE;
                    llMessageLinked(LINK_SET, LEASH_END_MOVEMENT,"","");
                    llMessageLinked(LINK_SET, DESUMMON_PARTICLES, "collarfront", "");
                    llTargetRemove(g_iLeashTarget);
                    g_iLeashedAuth = 0;
                    g_iFollowMode=FALSE;
                    llMessageLinked(LINK_SET, LM_SETTING_DELETE, "leash_leashedto", "");
                    llMessageLinked(LINK_SET, LM_SETTING_DELETE, "leash_follow", "");
                    llMessageLinked(LINK_SET, LM_SETTING_DELETE, "leash_leashedauth", "");
                    
                    llMessageLinked(LINK_SET, NOTIFY, "1%WEARERNAME% has been unleashed by "+SLURL(kID), g_kLeashedTo);
                    g_kLeashedTo = NULL;
                }
                
            }
        } else if(sChangetype == "length")
        {
            if(MaskOutranks(iNum, g_iLeashedAuth)){
                llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_length="+sChangevalue, "");
                g_fLength = (float)sChangevalue;
                llMessageLinked(LINK_SET, NOTIFY, "1Leash length now set to "+(string)g_fLength,kID);
            }
        } else if(sChangetype == "yank")
        {
            if(MaskOutranks(iNum, g_iLeashedAuth) && g_iLeashed){
                YankTo(kID);
                llMessageLinked(LINK_SET, NOTIFY, "0You yank %WEARERNAME%'s leash", kID);
                llMessageLinked(LINK_SET, NOTIFY, "0"+SLURL(kID)+" yanks your leash", g_kWearer);
            }
        } else if(sChangetype == "grab")
        {
            if(MaskOutranks(iNum, g_iLeashedAuth))
            {
                g_iFollowMode=FALSE;
                Leash(kID, iNum, TRUE);
                llMessageLinked(LINK_SET, NOTIFY, "0You grab %WEARERNAME%'s leash", kID);
                llMessageLinked(LINK_SET, NOTIFY, "0Your leash was grabbed by "+SLURL(kID), g_kWearer);
            }
        } else if(sChangetype == "holder")
        {
            llGiveInventory(kID, g_sLeashHolder);
        } else if(sChangetype == "tie")
        {
            // Anchor to a post
            if(MaskOutranks(iNum, g_iLeashedAuth))
            {
                key kTmp = (key)sChangevalue;
                if(kTmp){
                    g_iFollowMode = FALSE;
                    llMessageLinked(LINK_SET, NOTIFY, "0You take %WEARERNAME%'s leash and tie it to "+OSLURL(sChangevalue), kID);
                    Leash((key)sChangevalue, iNum, TRUE);
                    llMessageLinked(LINK_SET, NOTIFY, "0Your leash was tied to "+OSLURL(sChangevalue),g_kWearer);
                }else{
                    
                    g_kTempMenuUser = kID;
                    g_iTempMenuUser = iNum;
                    llSensor("","",SCRIPTED|PASSIVE,20,PI);
                    g_iAnchorMode=TRUE;
                }
            } else llMessageLinked(LINK_SET, NOTIFY, "0%NOACCESS% to tie the leash to a post", kID);
        } else if(sChangetype == "pass")
        {
            if(MaskOutranks(iNum, g_iLeashedAuth))
            {
                key kTmp = (key)sChangevalue;
                if(kTmp){
                    llMessageLinked(LINK_SET, NOTIFY, "1Asking "+SLURL(sChangevalue)+" to accept %WEARERNAME%'s leash", kID);
                    // Ask user to accept leash
                    llMessageLinked(LINK_SET, AUTH_REQUEST, "pass_leash", sChangevalue);
                }else{
                    g_kTempMenuUser = kID;
                    g_iTempMenuUser = iNum;
                    g_iAnchorMode=FALSE;
                    llSensor("","",AGENT,10,PI);
                }
            } else llMessageLinked(LINK_SET, NOTIFY, "0%NOACCESS% to passing the leash", kID);
        } else if(sChangetype == "follow"){
            if(MaskOutranks(iNum, g_iLeashedAuth))
            {
                key kTmp = (key)sChangevalue;
                llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_follow=1", "");
                g_iFollowMode=TRUE;
                if(kTmp)
                {
                    llMessageLinked(LINK_SET, NOTIFY, "1Asking "+SLURL(sChangevalue)+" if they want to be followed", kID);
                    llMessageLinked(LINK_SET, AUTH_REQUEST, "pass_follow", sChangevalue);
                }else{
                    if(sChangevalue == "me")
                    {
                        // Follow the command issuer
                        llMessageLinked(LINK_SET, DESUMMON_PARTICLES, "collarfront", "");
                        Leash(kID, iNum, TRUE);
                        llMessageLinked(LINK_SET, NOTIFY, "1Now following "+SLURL(kID), kID);
                    }else{
                        // Scan for follow!
                        g_iAnchorMode=FALSE;
                        g_kTempMenuUser=kID;
                        g_iTempMenuUser=iNum;
                        llSensor("","",AGENT,10,PI);
                        
                    }
                }
            }
        }
    }
}

Leash(key kAv, integer iAuth, integer iSave)
{
    if(!g_iFollowMode)
        llMessageLinked(LINK_SET, SUMMON_PARTICLES, "collarfront", kAv);
    if(iSave){
        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_leashedauth="+(string)iAuth,"");
        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_leashedto="+(string)kAv,"");
    }
    
    llSetTimerEvent(3.0);
    
    g_vPos = llList2Vector(llGetObjectDetails(g_kLeashedTo, [OBJECT_POS]), 0);
    //to prevent multiple target events and llMoveToTargets
    llTargetRemove(g_iLeashTarget);
    llStopMoveToTarget();
    g_iLeashTarget = llTarget(g_vPos, g_fLength);
}

SetLength(float iIn) {
    g_fLength = iIn;
    // llTarget needs to be changed to the new length if leashed
    if (g_kLeashedTo) {
        llTargetRemove(g_iLeashTarget);
        g_iLeashTarget = llTarget(g_vPos, g_fLength);
    }
}

LHSearch(){
    integer iBegin=0;
    integer iEnd = llGetInventoryNumber(INVENTORY_OBJECT);
    if(iEnd == 0)g_sLeashHolder="na";
    else{
        for(iBegin=0;iBegin<iEnd;iBegin++){
            string sItem  = llGetInventoryName(INVENTORY_OBJECT,iBegin);
            if(llSubStringIndex(llToLower(sItem),"leashholder")!=-1){
                g_sLeashHolder=sItem;
                sItem="";
                iBegin=0;
                iEnd=0;
                return;
            }
        }
    }
}
list g_lTextures = ["none", NULL_KEY, 
"Silk", "cdb7025a-9283-17d9-8d20-cee010f36e90",
"Chain", "4cde01ac-4279-2742-71e1-47ff81cc3529",
"Leather", "8f4c3616-46a4-1ed6-37dc-9705b754b7f1",
"Rope", "9a342cda-d62a-ae1f-fc32-a77a24a85d73"];

key GetTextureID()
{
    integer index = llListFindList(g_lTextures, [g_sParticleTexture]);
    return (key)llList2String(g_lTextures, index+1);
}

string g_sLeashHolder;
key g_kWearer;
list g_lOwner;
list g_lTrust;
list g_lBlock;
integer g_iLocked=FALSE;
list g_lChainPoints = [];
vector g_vPos;
integer g_iTurnMode;

ScanParticlePoints()
{
    g_lChainPoints=[];
    integer i=0;
    integer end = llGetNumberOfPrims();
    for(i=LINK_ROOT;i<=end;i++)
    {
        string name = llGetLinkName(i);
        string desc = llList2String(llGetLinkPrimitiveParams(i, [PRIM_DESC]),0);
        list lPar = llParseString2List(desc, ["~"],[]);
        integer index = llListFindList(lPar,["chainpoint"]);
        if(index!=-1)
        {
            g_lChainPoints += [ i, llList2String(lPar,index+1) ];
        } 
    }
    
    if(g_iVerbosity>=2)
    {
        llMessageLinked(LINK_SET, NOTIFY, "0Chainpoint scan completed: "+llDumpList2String(g_lChainPoints,"~"), g_kWearer);
    }
}
WipeAllChains()
{
    integer i=0;
    integer end = llGetListLength(g_lChainPoints);
    for(i=0;i<end;i+=2)
    {
        llLinkParticleSystem(i, []);
    }
}

YankTo(key kIn){
    llMoveToTarget(llList2Vector(llGetObjectDetails(kIn, [OBJECT_POS]), 0), 0.5);
    if (llGetAgentInfo(g_kWearer)&AGENT_SITTING) llMessageLinked(LINK_SET, RLV_CMD, "unsit=force", "");
    llSleep(2.0);
    llStopMoveToTarget();
}


vector g_vLeashColor = <1.00000, 1.00000, 1.00000>;
vector g_vLeashSize = <0.04, 0.04, 1.0>;
integer g_iParticleGlow = TRUE;
float g_fParticleAge = 3.5;
vector g_vLeashGravity = <0.0,0.0,-1.0>;
integer g_iParticleCount = 1;
float g_fBurstRate = 0.0;

string g_sLeashParticleMode;
string g_sParticleTexture = "Silk";
string g_sLeashParticleTexture;
string g_sParticleMode;

string g_sDefaultPoint = "Front";
StopParticles(integer iPrim)
{
    llLinkParticleSystem(iPrim,[]);
}


Particles(integer iLink, key kParticleTarget, vector vScale) {
    //when we have no target to send particles to, dont create any
    if(g_sLeashParticleMode == "noParticle") {
        StopParticles(iLink);
        return;
    }
    if (kParticleTarget == NULL) return;

    integer iFlags = PSYS_PART_FOLLOW_VELOCITY_MASK | PSYS_PART_TARGET_POS_MASK | PSYS_PART_FOLLOW_SRC_MASK;

    if (g_sParticleMode == "Ribbon") iFlags = iFlags | PSYS_PART_RIBBON_MASK;
    if (g_iParticleGlow) iFlags = iFlags | PSYS_PART_EMISSIVE_MASK;
    
    list lTemp = [
        PSYS_PART_MAX_AGE,g_fParticleAge,
        PSYS_PART_FLAGS,iFlags,
        PSYS_PART_START_COLOR, g_vLeashColor,
        //PSYS_PART_END_COLOR, g_vLeashColor,
        PSYS_PART_START_SCALE,vScale,
        //PSYS_PART_END_SCALE,g_vLeashSize,
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_DROP,
        PSYS_SRC_BURST_RATE,g_fBurstRate,
        PSYS_SRC_ACCEL, g_vLeashGravity,
        PSYS_SRC_BURST_PART_COUNT,g_iParticleCount,
        //PSYS_SRC_BURST_SPEED_MIN,fMinSpeed,
        //PSYS_SRC_BURST_SPEED_MAX,fMaxSpeed,
        PSYS_SRC_TARGET_KEY,kParticleTarget,
        PSYS_SRC_MAX_AGE, 0,
        PSYS_SRC_TEXTURE, GetTextureID()
        ];
    llLinkParticleSystem(iLink, lTemp);
}
key g_kTempMenuUser;
integer g_iTempMenuUser;
integer g_iAnchorMode = FALSE;

default
{
    on_rez(integer iNum){
        llResetScript();
    }
    state_entry(){
        llMessageLinked(LINK_SET, ALIVE, llGetScriptName(),"");
    }
    link_message(integer iSender, integer iNum, string sStr, key kID){
        if(iNum == REBOOT){
            llResetScript();
            
        } else if(iNum == READY){
            llMessageLinked(LINK_SET, ALIVE, llGetScriptName(), "");
        } else if(iNum == STARTUP){
            state active;
        }
    }
}
state active
{
    on_rez(integer t){
        if(llGetOwner()!=g_kWearer) llResetScript();
    }
    state_entry()
    {
        g_kWearer = llGetOwner();
        LHSearch();
        ScanParticlePoints();
        WipeAllChains();
    }
    no_sensor()
    {
        Dialog(g_kTempMenuUser, "\n[OpenCollar Leash Scan]\n\n> No objects/avatars found nearby that you can be leashed to", [], [UPMENU],0,g_iTempMenuUser, "leash~post");
    }
    
    sensor(integer n)
    {
        list lButtons;
        integer i=0;
        for(i=0;i<n;i++)
        {
            lButtons += llDetectedKey(i);
        }
        
        if(g_iAnchorMode)
            Dialog(g_kTempMenuUser, "\n[OpenCollar Leash Scan]\n\n", lButtons, [UPMENU],0,g_iTempMenuUser, "leash~post");
        else{
            if(!g_iFollowMode)
                Dialog(g_kTempMenuUser, "\n[OpenCollar Leash Scan]\n\n", lButtons, [UPMENU],0,g_iTempMenuUser, "leash~pass2");
            else
                Dialog(g_kTempMenuUser, "\n[OpenCollar Follow Scan]\n\n", lButtons, [UPMENU], 0, g_iTempMenuUser, "leash~follow");
        }
    }
    link_message(integer iSender,integer iNum,string sStr,key kID){
        if(iNum == COMMAND) {
            list lTmp = llParseString2List(sStr,["|>"],[]);
            integer iMask = llList2Integer(lTmp,0);
            string sCmd = llList2String(lTmp,1);
            UserCommand(iMask, sCmd, kID);
        }
        else if(iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
            llMessageLinked(iSender, MENUNAME_RESPONSE, g_sParentMenu+"|"+ g_sSubMenu,"");
        else if(iNum == DIALOG_RESPONSE){
            integer iMenuIndex = llListFindList(g_lMenuIDs, [kID]);
            if(iMenuIndex!=-1){
                string sMenu = llList2String(g_lMenuIDs, iMenuIndex+1);
                g_lMenuIDs = llDeleteSubList(g_lMenuIDs, iMenuIndex-1, iMenuIndex-2+g_iMenuStride);
                list lMenuParams = llParseString2List(sStr, ["|"],[]);
                key kAv = llList2Key(lMenuParams,0);
                string sMsg = llList2String(lMenuParams,1);
                integer iAuth = llList2Integer(lMenuParams,3);
                
                integer iRespring = TRUE;
                
                if(sMenu == "Menu~Main"){
                    if(sMsg == UPMENU) {
                        iRespring=FALSE;
                        llMessageLinked(LINK_SET, CMD_ZERO, "menu "+g_sParentMenu, kAv);
                    }
                    else if(sMsg == "Unleash") {
                        // Unleash
                        UserCommand(iAuth, "unleash", kAv);
                    } else if(sMsg == "Length")
                    {
                        Dialog(kAv, "[OpenCollar Leash]\n>Length\n\nEnter the new leash length. Any number from 0.1 - 50.0 is acceptable, and you can use numbers with decimals (ex. 3.5)", [],[],0,iAuth,"length");
                        iRespring=FALSE;
                    } else if(sMsg == "Yank")
                    {
                        UserCommand(iAuth, llToLower(sMsg), kAv);
                    } else if(sMsg == "Grab")
                    {
                        UserCommand(iAuth, llToLower(sMsg), kAv);
                    } else if(sMsg == "Give Holder"){
                        UserCommand(iAuth, "holder", kAv);
                    } else if(sMsg == "Configure")
                    {
                        ConfigMenu(kAv,iAuth);
                        iRespring=FALSE;
                    } else if(sMsg == "Tie")
                    {
                        UserCommand(iAuth,"tie",kAv);
                        iRespring=FALSE;
                    } else if(sMsg == "Pass")
                    {
                        UserCommand(iAuth,"pass",kAv);
                        iRespring=FALSE;
                    } else if(sMsg == "Follow"){
                        UserCommand(iAuth, "follow", kAv);
                        iRespring=FALSE;
                    }
                    
                    
                    if(iRespring)//Menu(kAv,iAuth);
                        llMessageLinked(LINK_SET, TIMEOUT_REGISTER, "4", "respring_menu:"+(string)kAv+":"+(string)iAuth);
                } else if(sMenu == "length")
                {
                    SetLength((float)sMsg);
                    Menu(kAv,iAuth);
                    
                    llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_length="+sMsg,"");
                } else if(sMenu == "Menu~Config")
                {
                    if(sMsg == UPMENU)
                    {
                        Menu(kAv,iAuth);
                        iRespring=FALSE;
                    } else if(sMsg == Checkbox(g_iTurnMode, "Turn"))
                    {
                        g_iTurnMode=1-g_iTurnMode;
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_turn="+(string)g_iTurnMode,"");
                    } else if(UnCheckbox(sMsg) == "Ribbon"){
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_texture=Silk","");
                    }else if(UnCheckbox(sMsg) == "Chain")
                    {
                        g_sParticleTexture = "Chain";
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_texture="+g_sParticleTexture,"");
                    } else if(UnCheckbox(sMsg) == "Leather")
                    {
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_texture=Leather","");
                    } else if(UnCheckbox(sMsg) == "Rope")
                    {
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_texture=Rope","");
                    } else if(sMsg == Checkbox(g_iNoLeash, "Invisible"))
                    {
                        g_iNoLeash=1-g_iNoLeash;
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_invis="+(string)g_iNoLeash,"");
                    } else if(sMsg == Checkbox(g_iParticleGlow, "Glow")){
                        g_iParticleGlow=1-g_iParticleGlow;
                        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_glow="+(string)g_iParticleGlow,"");
                    } else if(sMsg == "Color")
                    {
                        Dialog(kAv, "[zCollar Leash Color]", ["colormenu please"],[], 0, iAuth, "leash~color");
                        iRespring = FALSE;
                    } else if(sMsg == "* GRAVITY")
                    {
                        Dialog(kAv, "[zCollar Leash Gravity]\n\nCurrent Gravity: "+(string)(g_vLeashGravity.z),[],[],0,iAuth,"leash~gravity");
                        iRespring=FALSE;
                    } else if(sMsg == "* SIZE")
                    {
                        Dialog(kAv, "[zCollar Leash Size]\n\nCurrent Size: "+(string)(g_vLeashSize.x), [],[],0,iAuth,"leash~size");
                        iRespring=FALSE;
                    }
                    
                    
                    if(iRespring)ConfigMenu(kAv,iAuth);
                } else if(sMenu == "leash~post")
                {
                    if(sMsg == UPMENU)
                    {
                        Menu(kAv,iAuth);
                        return;
                    }else {
                        UserCommand(iAuth, "tie "+sMsg, kAv);
                        Menu(kAv,iAuth);
                    }
                } else if(sMenu == "leash~pass")
                {
                    if(sMsg == "No")
                    {
                        return;
                    }else if(sMsg == "Yes")
                    {
                        g_iLeashedAuth = 0;
                        UserCommand(iAuth, "grab", kAv);
                    }
                } else if(sMenu == "leash~color")
                {
                    llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_color="+sMsg, "");
                    ConfigMenu(kAv,iAuth);
                } else if(sMenu == "leash~pass2")
                {
                    UserCommand(iAuth,"pass "+sMsg, kAv);
                } else if(sMenu == "leash~follow"){
                    UserCommand(iAuth, "follow "+sMsg, kAv);
                } else if(sMenu == "leash~follower")
                {
                    if(sMsg == "No")
                    {
                        g_iFollowMode=FALSE;
                        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "leash_follow","");
                        
                        llMessageLinked(LINK_SET, NOTIFY, "0Follow denied by "+SLURL(kAv), g_kWearer);
                    } else if(sMsg == "Yes")
                    {
                        // Accepted
                        Leash(kAv, iAuth, TRUE);
                        llMessageLinked(LINK_SET, DESUMMON_PARTICLES, "collarfront", "");
                        llMessageLinked(LINK_SET, NOTIFY, "1Now following "+SLURL(kAv), kAv);
                    }
                } else if(sMenu == "leash~gravity"){
                    llMessageLinked(LINK_SET,LM_SETTING_SAVE,"leash_gravity="+sMsg,"");
                    ConfigMenu(kAv,iAuth);
                } else if(sMenu == "leash~size"){
                    llMessageLinked(LINK_SET, LM_SETTING_SAVE, "leash_size="+sMsg,"");
                    ConfigMenu(kAv,iAuth);
                }
            }
        } else if (iNum == DIALOG_TIMEOUT) {
            integer iMenuIndex = llListFindList(g_lMenuIDs, [kID]);
            g_lMenuIDs = llDeleteSubList(g_lMenuIDs, iMenuIndex - 1, iMenuIndex +3);  //remove stride from g_lMenuIDs
        } else if(iNum == LM_SETTING_RESPONSE){
            // Detect here the Settings
            list lSettings = llParseString2List(sStr, ["_","="],[]);
            string sToken = llList2String(lSettings,0);
            string sVar = llList2String(lSettings,1);
            string sVal = llList2String(lSettings,2);
            integer iUpdateParticles=FALSE;
            
            
            if(sToken=="leash"){
                if(sVar=="leashedto"){
                    // Start Particles. The particles will be updated with new parameters as they get received.
                    g_kLeashedTo = (key)sVal;
                    g_iLeashed=TRUE;
                    iUpdateParticles=TRUE;
                    
                } else if(sVar == "leashedauth")
                {
                    g_iLeashedAuth = (integer)sVal;
                } else if(sVar == "length")
                {
                    SetLength((float)sVal);
                } else if(sVar == "turn")
                {
                    g_iTurnMode = (integer)sVal;
                } else if(sVar == "texture")
                {
                    iUpdateParticles=TRUE;
                    g_sParticleTexture = sVal;
                    if(g_sParticleTexture!="Silk")g_sParticleMode="Normal";
                    else g_sParticleMode="Ribbon";
                } else if(sVar == "invis")
                {
                    g_iNoLeash = (integer)sVal;
                    if(g_iNoLeash){
                        g_sParticleTexture="none";
                        g_sLeashParticleMode="noParticle";
                    }
                    else g_sLeashParticleMode="";
                    iUpdateParticles=TRUE;
                } else if(sVar == "glow")
                {
                    g_iParticleGlow = (integer)sVal;
                    iUpdateParticles=TRUE;
                } else if(sVar == "color")
                {
                    g_vLeashColor = (vector)sVal;
                    iUpdateParticles=TRUE;
                } else if(sVar == "follow"){
                    g_iFollowMode=(integer)sVal;
                    if(g_iFollowMode)llMessageLinked(LINK_SET, DESUMMON_PARTICLES, "collarfront", "");
                } else if(sVar == "gravity"){
                    g_vLeashGravity.z=(float)sVal;
                    iUpdateParticles=TRUE;
                } else if(sVar == "size")
                {
                    g_vLeashSize.x = (float)sVal;
                    g_vLeashSize.y = (float)sVal;
                    iUpdateParticles=TRUE;
                }
                
                
                if(iUpdateParticles && g_iLeashed && !g_iFollowMode)llMessageLinked(LINK_SET, SUMMON_PARTICLES, "collarfront", g_kLeashedTo);
            } else if(sToken == "global")
            {
                if(sVar == "checkboxes")
                {
                    g_lCheckboxes = llParseString2List(sVal, [","],[]);
                } else if(sVar == "verbosity")
                {
                    g_iVerbosity = (integer)sVal;
                }
            }
            
            
            
            if(sStr == "settings=sent")
            {
                ScanParticlePoints();
                if(g_iLeashed)
                    Leash(g_kLeashedTo, g_iLeashedAuth, FALSE);
            }
        } else if(iNum == REBOOT)
        {
            llResetScript();
        }else if(iNum == QUERY_POINT_KEY)
        {
            integer iIndex=llListFindList(g_lChainPoints, [sStr]);
            if(iIndex!=-1)
            {
                llMessageLinked(LINK_SET, REPLY_POINT_KEY, kID, llGetLinkKey(llList2Integer(g_lChainPoints,iIndex-1)));
            }
        } else if(iNum == REPLY_POINT_KEY)
        {
            if(HasDSRequest((key)sStr)!=-1){
                string meta = GetDSMeta((key)sStr);
                DeleteDSReq((key)sStr);
                list lTmp = llParseString2List(meta, ["|"],[]);
                integer iIndex = llListFindList(g_lChainPoints, [llList2String(lTmp,0)]);
                if(iIndex == -1 )return;
                integer iPrim = llList2Integer(g_lChainPoints, iIndex-1);
                list mine = [ iPrim, llGetLinkKey(iPrim) ];
                key kTarget = (key)llList2String(lTmp,1);
                if(kTarget)
                    Particles(iPrim, kTarget, g_vLeashSize);
                else
                    Particles(iPrim, kID, g_vLeashSize);
            }
        } else if(iNum == SUMMON_PARTICLES)
        {
            list lTmp = llParseString2List(sStr, ["|"],[]);
            if(llListFindList(g_lChainPoints, [llList2String(lTmp,0)])!=-1)
            {
                if(llGetListLength(lTmp)==1){
                    key ident = llGenerateKey();
                    UpdateDSRequest(NULL, ident, llList2String(lTmp,0)+"|"+(string)kID);

                    llMessageLinked(LINK_SET, QUERY_POINT_KEY, llList2String(lTmp,0), ident);
                    llMessageLinked(LINK_SET, TIMEOUT_REGISTER, "5", "cuff_link_expire:"+(string)ident);
                } else {
                    key ident = llGenerateKey();
                    UpdateDSRequest(NULL, ident, llList2String(lTmp,0)+"|"+llList2String(lTmp,1));
                    
                    llMessageLinked(LINK_SET, QUERY_POINT_KEY, llList2String(lTmp,1), ident);
                    llMessageLinked(LINK_SET, TIMEOUT_REGISTER, "5", "cuff_link_expire:"+(string)ident);
                }
            }else{
                if(g_iVerbosity>=2){
                    llMessageLinked(LINK_SET, NOTIFY, "0Chainpoint "+llList2String(lTmp,0)+" not found in list: "+llDumpList2String(g_lChainPoints,"~"), g_kWearer);
                }
            }
        } else if(iNum == CLEAR_ALL_CHAINS)
        {
            WipeAllChains();
        }else if(iNum == TIMEOUT_FIRED){
            //llSay(0, "timer fired: "+sStr);
            list lTmp = llParseString2List(sStr, [":"],[]);
            if(llList2String(lTmp,0) == "cuff_link_expire")
            {
                key ident = (key)llList2String(lTmp,1);
                if(HasDSRequest(ident)!=-1){
                    DeleteDSReq(ident);
                }
            } else if(llList2String(lTmp,0)=="respring_menu"){
                Menu((key)llList2String(lTmp,1), (integer)llList2String(lTmp,2));
            }
        } else if(iNum == DESUMMON_PARTICLES)
        {
            integer index = llListFindList(g_lChainPoints, [sStr]);
            if(index!=-1){
                integer linkNum = llList2Integer(g_lChainPoints,index-1);
                llLinkParticleSystem(linkNum, []);
            }
        } else if(iNum == AUTH_REPLY)
        {
            list lTmp = llParseString2List(sStr,["|"],[]);
            if(kID == "pass_leash")
            {
                if(llList2String(lTmp,0)=="AuthReply")
                {
                    key kAv = (key)llList2String(lTmp,1);
                    integer iAuth = (integer)llList2String(lTmp,2);
                    Dialog(kAv, "\n[OpenCollar Leash Pass]\n\nDo you want to accept %WEARERNAME%'s leash?", [],["Yes", "No"],0,iAuth,"leash~pass");
                }
            } else if(kID == "pass_follow")
            {
                key kAv = (key)llList2String(lTmp,1);
                integer iAuth = (integer)llList2String(lTmp,2);
                Dialog(kAv, "\n[OpenCollar Follow]\n\nDo you want to let %WEARERNAME% follow you?", [], ["Yes", "No"],0,iAuth,"leash~follower");
            }
        } else if(iNum == LEASH_START_MOVEMENT)g_iAlreadyMoving=TRUE;
        else if(iNum == LEASH_END_MOVEMENT)g_iAlreadyMoving=FALSE;
        //llOwnerSay(llDumpList2String([iSender,iNum,sStr,kID],"^"));
    }
    
    at_target(integer iTarget, vector vTarget, vector vCur)
    {
        llStopMoveToTarget();
        llTargetRemove(g_iLeashTarget);
        
        
        g_vPos = llList2Vector(llGetObjectDetails(g_kLeashedTo,[OBJECT_POS]),0);
        g_iLeashTarget = llTarget(g_vPos, g_fLength);
        
        if(g_iJustMoved) {
            vector pointTo = llList2Vector(llGetObjectDetails(g_kLeashedTo,[OBJECT_POS]),0) - llGetPos();
            float  turnAngle = llAtan2(pointTo.x, pointTo.y);// - myAngle;
            if (g_iTurnMode) llMessageLinked(LINK_SET, RLV_CMD, "setrot:" + (string)(turnAngle) + "=force", NULL_KEY);   //transient command, doesn;t need our fakekey
            g_iJustMoved = 0;
        }
        
        if(g_iAlreadyMoving){
            g_iAlreadyMoving=FALSE;
            llMessageLinked(LINK_SET, LEASH_END_MOVEMENT, "", "");
        }
    }
    
    
    not_at_target() {
        g_iJustMoved = 1;
        // i ran into a problem here which seems to be "speed" related, specially when using the menu to unleash this event gets triggered together or just after the CleanUp() function
        //to prevent to get stay in the target events i added a check on g_kLeashedTo is NULL_KEY
        if(g_kLeashedTo) {
            vector vNewPos = llList2Vector(llGetObjectDetails(g_kLeashedTo,[OBJECT_POS]),0);
            if (g_vPos != vNewPos) {
                llTargetRemove(g_iLeashTarget);
                g_vPos = vNewPos;
                g_iLeashTarget = llTarget(g_vPos, g_fLength);
            }
            if (g_vPos != ZERO_VECTOR){
                // The below code was causing users to fly if the z height of the person holding the leash was different.
                
                
                //vector currentPos = llGetPos();
                //g_vPos = <g_vPos.x, g_vPos.y, currentPos.z>;
                llMoveToTarget(g_vPos,1.0);
            }
            else{
                llStopMoveToTarget();
                llTargetRemove(g_iLeashTarget);
            }
            
            
            if(!g_iAlreadyMoving) {
                g_iAlreadyMoving=TRUE;
                llMessageLinked(LINK_SET, LEASH_START_MOVEMENT, "","");
            }
        } else {
            llStopMoveToTarget();
            g_iAlreadyMoving=FALSE;
            llMessageLinked(LINK_SET, LEASH_END_MOVEMENT,"","");
            llTargetRemove(g_iLeashTarget);
            UserCommand(C_COLLAR_INTERNALS, "unleash", llGetKey());
        }
    }
    
    timer()
    {
        
        vector vLeashedToPos=llList2Vector(llGetObjectDetails(g_kLeashedTo,[OBJECT_POS]),0);
        integer iIsInSimOrJustOutside=TRUE;
        if(vLeashedToPos == ZERO_VECTOR || llVecDist(llGetPos(), vLeashedToPos)> 255) iIsInSimOrJustOutside=FALSE;
        
        if (iIsInSimOrJustOutside && llVecDist(llGetPos(),vLeashedToPos)<(60+g_fLength)) {
            if(!g_iLeasherInRange) { //and the leasher was previously not in range
                if (g_iAwayCounter) {
                    g_iAwayCounter = -1;
                    llSetTimerEvent(3.0);
                }
                //Debug("leashing with "+g_sCheck);
                
                if(!g_iFollowMode){
                    llMessageLinked(LINK_SET, SUMMON_PARTICLES, "collarfront", g_kLeashedTo);
                }
                
                
                g_iLeasherInRange = TRUE;

                llTargetRemove(g_iLeashTarget);
                g_vPos = vLeashedToPos;
                g_iLeashTarget = llTarget(g_vPos, g_fLength);
                if (g_vPos != ZERO_VECTOR) llMoveToTarget(g_vPos, 0.8);
                //ApplyRestrictions();
                
                if(!g_iAlreadyMoving) llMessageLinked(LINK_SET, LEASH_START_MOVEMENT,"","");
            }
        }else{
            if(g_iLeasherInRange) {  //but was a short while ago
                if (g_iAwayCounter <= llGetUnixTime()) {
                    llTargetRemove(g_iLeashTarget);
                    llStopMoveToTarget();
                    if(!g_iFollowMode)
                        llMessageLinked(LINK_SET, DESUMMON_PARTICLES, "collarfront", "");
                    g_iLeasherInRange=FALSE;
                    //ApplyRestrictions();
                    if(g_iAlreadyMoving)llMessageLinked(LINK_SET, LEASH_END_MOVEMENT,"","");
                } else if(g_iAwayCounter==-1){
                    g_iAwayCounter = llGetUnixTime()+15;
                }
            } else {
                // nothing else to do with the away counter
                // slow down the timer
                llSetTimerEvent(11);
            }
        }
    }
        
}
