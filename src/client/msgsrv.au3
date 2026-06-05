; =============================================================================
; msgAH.au3 - MsgSrv Client v2.4
; Corrections :
;   - TrayOnEventMode=1 : le bouton Quitter quitte réellement l'applicatif
;   - Config AD lue depuis le config.ini du serveur (pas path.ini)
;   - Failback explicite : sans service détecté, tout message "ALL" est affiché
; =============================================================================
#include <GUIConstantsEx.au3>
#include <Misc.au3>
#include <WindowsConstants.au3>
#include <IE.au3>
#include <File.au3>
#include <TrayConstants.au3>

If _Singleton("msgsrv.exe", 1) = 0 Then Exit

; ---------- Mode tray : callbacks directs (plus fiable que TrayGetMsg) --------
; TrayOnEventMode=1 : les fonctions On* sont appelées automatiquement même
; pendant un Sleep(), sans boucle de polling manuelle.
Opt("TrayOnEventMode", 1)
Opt("TrayMenuMode",    1)   ; Supprime les items AutoIt par défaut (Pause/Exit)
Opt("TrayIconHide",    0)   ; Icône visible dans la zone de notification

; ---------- Lecture path.ini -------------------------------------------------
Global $g_sPathIni = @ScriptDir & "\path.ini"
If Not FileExists($g_sPathIni) Then
    MsgBox(16, "Erreur", "Fichier path.ini introuvable.")
    Exit
EndIf

Global $g_sFichier    = IniRead($g_sPathIni, "Chemins", "Message",    @ScriptDir & "\message.txt")
Global $g_sConfig     = IniRead($g_sPathIni, "Chemins", "Config",     @ScriptDir & "\config.ini")
Global $g_sTypesFile  = IniRead($g_sPathIni, "Chemins", "Types",      "")
Global $g_sIntervalle = Int(IniRead($g_sPathIni, "Chemins", "Intervalle", "6000"))

; ---------- Icône -----------------------------------------------------------
Local $sIconPath = @ScriptDir & "\icon.ico"
If FileExists($sIconPath) Then TraySetIcon($sIconPath)
TraySetToolTip("MsgSrv - Initialisation...")

; ---------- Identité --------------------------------------------------------
Global $g_sUser    = @UserName
; La config AD (serveur LDAP, BaseDN) est lue depuis le config.ini du serveur,
; géré par l'administrateur via adminmsgAH.exe → onglet Configuration.
Global $g_sService = _GetUserService($g_sUser)

Global $g_sLastUID      = ""
Global $g_sLastMsgTime  = ""
Global $g_sLastMsgObjet = ""

; =============================================================================
; MENU TRAY (créé après initialisation du service pour afficher la bonne valeur)
; =============================================================================
Global $g_trayTitle = TrayCreateItem("MsgSrv - Messagerie interne")
TrayItemSetState($g_trayTitle, $TRAY_DISABLE)
TrayCreateItem("")

Global $g_trayUser    = TrayCreateItem("Utilisateur : " & $g_sUser)
TrayItemSetState($g_trayUser, $TRAY_DISABLE)

Global $g_trayService = TrayCreateItem( _
    "Service     : " & ($g_sService = "" ? "(non detecte - voir failback)" : $g_sService))
TrayItemSetState($g_trayService, $TRAY_DISABLE)
TrayCreateItem("")

Global $g_trayStatus  = TrayCreateItem("Etat        : en cours...")
TrayItemSetState($g_trayStatus, $TRAY_DISABLE)

Global $g_trayLastMsg = TrayCreateItem("Dernier msg : Aucun depuis le demarrage")
TrayItemSetState($g_trayLastMsg, $TRAY_DISABLE)
TrayCreateItem("")

; Bouton Quitter — avec TrayOnEventMode=1, le callback _OnQuit est appelé
; directement au clic, même pendant un Sleep.
Global $g_trayQuit = TrayCreateItem("Quitter")
TrayItemSetOnEvent($g_trayQuit, "_OnQuit")

_MAJ_Tray()

; =============================================================================
; BOUCLE PRINCIPALE — simple et lisible grâce aux callbacks tray
; =============================================================================
While True
    _CheckForNewMessage()
    _MAJ_Tray()
    Sleep($g_sIntervalle)
WEnd

; =============================================================================
; CALLBACK TRAY — appelé directement par AutoIt sans boucle de polling
; =============================================================================
Func _OnQuit()
    Exit
EndFunc

; =============================================================================
; VÉRIFICATION D'UN NOUVEAU MESSAGE
; =============================================================================
Func _CheckForNewMessage()
    Local $sSilencieux = IniRead($g_sConfig, "Parametres", "Silencieux", "0")
    If $sSilencieux = "1" Then Return
    If Not FileExists($g_sFichier) Then Return

    Local $sContenu = FileRead($g_sFichier)
    Local $sUID     = _ExtractTag($sContenu, "uuid")

    If $sUID = "" Or $sUID = $g_sLastUID Then Return

    $g_sLastUID = $sUID
    If _EstDestinataire($sContenu) Then
        $g_sLastMsgTime  = @HOUR & "h" & @MIN & " le " & @MDAY & "/" & @MON
        $g_sLastMsgObjet = _ExtractFirstLine($sContenu)
        _AfficherMessage($sContenu)
    EndIf
EndFunc

; =============================================================================
; MISE À JOUR DU MENU ET DU TOOLTIP
; =============================================================================
Func _MAJ_Tray()
    Local $sSilencieux = IniRead($g_sConfig, "Parametres", "Silencieux", "0")
    Local $sEtat = ($sSilencieux = "1") ? "Silencieux (messages bloques)" : "Actif - en ecoute"

    Local $sSrvDisplay = $g_sService
    If $sSrvDisplay = "" Then $sSrvDisplay = "non detecte (tous les msg ALL recus)"

    TraySetToolTip("MsgSrv" & @LF & _
        "Utilisateur : " & $g_sUser  & @LF & _
        "Service     : " & $sSrvDisplay & @LF & _
        "Etat        : " & $sEtat)

    TrayItemSetText($g_trayStatus, "Etat        : " & $sEtat)

    If $g_sLastMsgObjet <> "" Then
        Local $sObjetDisplay = $g_sLastMsgObjet
        If StringLen($sObjetDisplay) > 38 Then $sObjetDisplay = StringLeft($sObjetDisplay, 35) & "..."
        TrayItemSetText($g_trayLastMsg, "Dernier msg : " & $g_sLastMsgTime & " - " & $sObjetDisplay)
    EndIf
EndFunc

; =============================================================================
; FILTRAGE — FAILBACK INTÉGRÉ
; =============================================================================
Func _EstDestinataire($sContenu)
    Local $sServices = _ExtractTag($sContenu, "services")

    ; Cas 1 : message diffusé à tout le monde
    If $sServices = "" Or $sServices = "ALL" Then Return True

    ; Cas 2 (FAILBACK) : service non détecté (AD inaccessible, poste hors domaine...)
    ; → l'utilisateur reçoit tous les messages ciblés "ALL" (cas 1 ci-dessus).
    ; Pour les messages ciblés par service, on ne peut pas savoir s'il est concerné,
    ; donc on ne l'affiche pas (évite le spam). Ce comportement peut être
    ; inversé ci-dessous en remplaçant "Return False" par "Return True".
    If $g_sService = "" Then Return False

    ; Cas 3 : vérification du service dans la liste des destinataires
    Local $aList = StringSplit($sServices, ";", 2)
    For $i = 0 To UBound($aList) - 1
        If $aList[$i] = $g_sService Then Return True
    Next
    Return False
EndFunc

; =============================================================================
; DÉTECTION DU SERVICE AD
; La config LDAP (serveur, BaseDN) est lue depuis le config.ini du SERVEUR,
; dont le chemin est fourni par path.ini → clé Config=
; Ce fichier est géré par l'admin via adminmsgAH.exe > onglet Configuration.
; =============================================================================
Func _GetUserService($sUsername)
    ; Tentative via AD avec la config du serveur
    Local $sDept = _ADGetDept($sUsername)
    If $sDept <> "" Then Return $sDept

    ; Fallback 1 : fichier service.ini local (posé à côté du client)
    Local $sLocal = @ScriptDir & "\service.ini"
    If FileExists($sLocal) Then
        Local $sSrv = IniRead($sLocal, "User", "Service", "")
        If $sSrv <> "" Then Return $sSrv
    EndIf

    ; Fallback 2 : aucun service → failback activé dans _EstDestinataire
    Return ""
EndFunc

Func _ADGetDept($sUsername)
    Local $oErr = ObjEvent("AutoIt.Error", "_ADErrHandler")

    ; Lecture de la config AD depuis le config.ini du serveur
    Local $sServer = IniRead($g_sConfig, "ActiveDirectory", "Server", "")
    Local $sBaseDN = IniRead($g_sConfig, "ActiveDirectory", "BaseDN", "")

    Local $sRootURL = "LDAP://" & ($sServer <> "" ? $sServer & "/" : "") & "RootDSE"
    Local $oRoot = ObjGet($sRootURL)
    If @error Or Not IsObj($oRoot) Then Return ""

    If $sBaseDN = "" Then
        $sBaseDN = $oRoot.defaultNamingContext
        If @error Or $sBaseDN = "" Then Return ""
    EndIf

    Local $sBase = "LDAP://" & ($sServer <> "" ? $sServer & "/" : "") & $sBaseDN
    Local $oConn = ObjCreate("ADODB.Connection")
    If @error Or Not IsObj($oConn) Then Return ""
    Local $oCmd = ObjCreate("ADODB.Command")
    If @error Or Not IsObj($oCmd) Then Return ""

    $oConn.Provider = "ADsDSOObject"
    $oConn.Open("Active Directory Provider")
    If @error Then Return ""

    $oCmd.ActiveConnection = $oConn
    $oCmd.CommandText = "<" & $sBase & ">;" & _
        "(&(objectClass=user)(sAMAccountName=" & $sUsername & "));department;subtree"
    $oCmd.Properties("Page Size") = 1

    Local $oRS = $oCmd.Execute()
    If @error Or Not IsObj($oRS) Then
        $oConn.Close()
        Return ""
    EndIf

    Local $sRes = ""
    If Not $oRS.EOF Then
        $sRes = $oRS.Fields("department").Value
        If @error Then $sRes = ""
    EndIf
    $oRS.Close()
    $oConn.Close()
    Return $sRes
EndFunc

Func _ADErrHandler()
EndFunc

; =============================================================================
; EXTRACTION DES BALISES
; =============================================================================
Func _ExtractTag($sContenu, $sTag)
    If $sTag = "" Then Return ""
    Local $aLines = StringSplit($sContenu, @CRLF, 1)
    Local $bNext  = False
    For $i = 1 To $aLines[0]
        If $bNext Then
            Local $sLine = StringStripWS($aLines[$i], 3)
            If $sLine <> "" Then Return $sLine
        EndIf
        If $aLines[$i] = "[" & $sTag & "]" Then $bNext = True
    Next
    Return ""
EndFunc

; Retourne l'objet du message (première ligne de texte après le tag de type)
Func _ExtractFirstLine($sContenu)
    Local $aLines = StringSplit($sContenu, @CRLF, 1)
    Local $sTypeID = ""
    For $i = 1 To $aLines[0]
        Local $sLine = $aLines[$i]
        If StringLeft($sLine, 1) = "[" And StringRight($sLine, 1) = "]" Then
            Local $sTag = StringTrimLeft(StringTrimRight($sLine, 1), 1)
            Local $bIsType = False
            If $g_sTypesFile <> "" And FileExists($g_sTypesFile) Then
                $bIsType = (IniRead($g_sTypesFile, $sTag, "label", "") <> "")
            Else
                $bIsType = StringInStr("info|alerte|urgence", $sTag) > 0
            EndIf
            If $bIsType Then $sTypeID = $sTag
        ElseIf $sTypeID <> "" And StringStripWS($sLine, 3) <> "" Then
            Return StringStripWS($sLine, 3)
        EndIf
    Next
    Return ""
EndFunc

Func _GetTypeIDFromContenu($sContenu)
    Local $aLines = StringSplit($sContenu, @CRLF, 1)
    For $i = 1 To $aLines[0]
        Local $sLine = $aLines[$i]
        If StringLeft($sLine, 1) = "[" And StringRight($sLine, 1) = "]" Then
            Local $sTag = StringTrimLeft(StringTrimRight($sLine, 1), 1)
            Local $bIsType = False
            If $g_sTypesFile <> "" And FileExists($g_sTypesFile) Then
                $bIsType = (IniRead($g_sTypesFile, $sTag, "label", "") <> "")
            Else
                $bIsType = StringInStr("info|alerte|urgence", $sTag) > 0
            EndIf
            If $bIsType Then Return $sTag
        EndIf
    Next
    Return "info"
EndFunc

Func _ParseMessage($sContenu)
    ; [0]=typeID [1]=objet [2]=corps HTML [3]=image [4]=signature
    Local $aData[5]
    $aData[0] = "info"
    Local $aLines  = StringSplit($sContenu, @CRLF, 1)
    Local $sTag    = ""
    Local $sTypeID = ""
    Local $sMsg    = ""
    For $i = 1 To $aLines[0]
        Local $sLine = $aLines[$i]
        If StringLeft($sLine, 1) = "[" And StringRight($sLine, 1) = "]" Then
            $sTag = StringTrimLeft(StringTrimRight($sLine, 1), 1)
            Local $bIsType = False
            If $g_sTypesFile <> "" And FileExists($g_sTypesFile) Then
                $bIsType = (IniRead($g_sTypesFile, $sTag, "label", "") <> "")
            Else
                $bIsType = StringInStr("info|alerte|urgence", $sTag) > 0
            EndIf
            If $bIsType Then
                $aData[0] = $sTag
                $sTypeID  = $sTag
            EndIf
        Else
            Switch $sTag
                Case $sTypeID
                    If $aData[1] = "" Then
                        $aData[1] = $sLine
                    ElseIf $sLine <> "" Then
                        $sMsg &= $sLine & "<br>"
                    EndIf
                Case "image"
                    If $aData[3] = "" And $sLine <> "" Then $aData[3] = $sLine
                Case "signature"
                    If $aData[4] = "" And $sLine <> "" Then $aData[4] = $sLine
            EndSwitch
        EndIf
    Next
    $aData[2] = $sMsg
    Return $aData
EndFunc

; =============================================================================
; COULEURS
; =============================================================================
Func _GetTypeColors($sTypeID)
    Local $aColors[4]
    Switch $sTypeID
        Case "alerte"
            $aColors[0] = "#FFF8E1"
            $aColors[1] = "#6B4000"
            $aColors[2] = "#E67E00"
            $aColors[3] = "Alerte"
        Case "urgence"
            $aColors[0] = "#FFF0F0"
            $aColors[1] = "#7A0000"
            $aColors[2] = "#CC0000"
            $aColors[3] = "URGENCE"
        Case Else
            $aColors[0] = "#E7F3FF"
            $aColors[1] = "#003087"
            $aColors[2] = "#0057B7"
            $aColors[3] = "Information"
    EndSwitch
    If $g_sTypesFile <> "" And FileExists($g_sTypesFile) Then
        Local $sBg     = IniRead($g_sTypesFile, $sTypeID, "bgColor",     "")
        Local $sTxt    = IniRead($g_sTypesFile, $sTypeID, "textColor",   "")
        Local $sBan    = IniRead($g_sTypesFile, $sTypeID, "bannerColor", "")
        Local $sBanLbl = IniRead($g_sTypesFile, $sTypeID, "bannerLabel", "")
        If $sBg     <> "" Then $aColors[0] = "#" & $sBg
        If $sTxt    <> "" Then $aColors[1] = "#" & $sTxt
        If $sBan    <> "" Then $aColors[2] = "#" & $sBan
        If $sBanLbl <> "" Then $aColors[3] = $sBanLbl
    EndIf
    Return $aColors
EndFunc

; =============================================================================
; AFFICHAGE DU MESSAGE
; =============================================================================
Func _AfficherMessage($sContenu)
    Local $aData   = _ParseMessage($sContenu)
    Local $sTypeID = $aData[0]
    Local $sObjet  = $aData[1]
    Local $sMsg    = $aData[2]
    Local $sImg    = $aData[3]
    Local $sSig    = $aData[4]
    Local $aColors = _GetTypeColors($sTypeID)

    Local $sImgBlock = ""
    If $sImg <> "" And FileExists($sImg) Then
        $sImgBlock = "<div style='text-align:center;margin-top:14px;'>" & _
            "<img src='file:///" & StringReplace($sImg, "\", "/") & "'" & _
            " style='max-width:440px;max-height:260px;border-radius:6px;border:1px solid #ccc;'></div>"
    EndIf

    Local $sSigBlock = ""
    If $sSig <> "" Then
        $sSigBlock = "<p style='text-align:right;font-style:italic;" & _
            "font-size:13px;color:#666;margin-top:18px;'>" & $sSig & "</p>"
    EndIf

    Local $sHTML = "<!DOCTYPE html><html><head><meta charset='utf-8'>" & _
        "<style>" & _
        "* { box-sizing:border-box; }" & _
        "body { margin:0;padding:0;font-family:'Segoe UI',sans-serif;background:" & $aColors[0] & ";}" & _
        ".banner { background:" & $aColors[2] & ";color:#fff;padding:10px 18px;font-size:14px;font-weight:bold;}" & _
        ".content { padding:18px 22px;color:" & $aColors[1] & ";}" & _
        "h2 { margin:0 0 10px;font-size:17px;}" & _
        "p  { font-size:14px;line-height:1.65;margin:0;}" & _
        "</style></head><body>" & _
        "<div class='banner'>" & $aColors[3] & "</div>" & _
        "<div class='content'><h2>" & $sObjet & "</h2><p>" & $sMsg & "</p>" & _
        $sImgBlock & $sSigBlock & "</div></body></html>"

    Local $hGUI = GUICreate("Message - " & $g_sUser, 500, 420, -1, -1, _
        BitOR($WS_POPUP, $WS_BORDER, $WS_SYSMENU, $WS_CAPTION))
    GUISetBkColor(0xFFFFFF)

    Local $oIE    = _IECreateEmbedded()
    GUICtrlCreateObj($oIE, 0, 0, 500, 370)
    Local $btnClose = GUICtrlCreateButton("J'ai lu ce message", 155, 378, 190, 32)
    GUICtrlSetFont($btnClose, 10, 700, 0, "Segoe UI")

    GUISetState(@SW_SHOW, $hGUI)
    WinActivate($hGUI)

    _IENavigate($oIE, "about:blank")
    While _IEPropertyGet($oIE, "busy")
        Sleep(100)
    WEnd
    _IEDocWriteHTML($oIE, $sHTML)

    ; En mode TrayOnEventMode=1, _OnQuit() peut être appelé pendant ce GUIGetMsg
    While True
        Local $guiMsg = GUIGetMsg()
        If $guiMsg = $GUI_EVENT_CLOSE Or $guiMsg = $btnClose Then ExitLoop
        Sleep(50)
    WEnd
    GUIDelete($hGUI)
EndFunc
