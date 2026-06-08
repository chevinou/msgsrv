; =============================================================================
; adminmsg.au3 - MsgSrv Admin v2.2
; v2.2 : ListView à coches pour les services (scalable 50+),
;        filtre dynamique, pas de requête AD au démarrage.
; =============================================================================
#include <GUIConstantsEx.au3>
#include <Misc.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ComboConstants.au3>
#include <File.au3>
#include <Array.au3>
#include <WinAPIConv.au3>
#include <WinAPI.au3>
#include <GuiTab.au3>
#include <GuiListView.au3>
#include <ListViewConstants.au3>
#include <ButtonConstants.au3>
#include <StaticConstants.au3>
#include <Crypt.au3>

If _Singleton("adminmsg.exe", 1) = 0 Then Exit

; ---------- Chemins ----------------------------------------------------------
Global $g_sBase      = @ScriptDir
Global $g_sFichier   = $g_sBase & "\message.txt"
Global $g_sConfig    = $g_sBase & "\config.ini"
Global $g_sLogFile   = $g_sBase & "\log.txt"
Global $g_sImgFolder = $g_sBase & "\img"
Global $g_sUsersFile = $g_sBase & "\users.ini"
Global $g_sServFile  = $g_sBase & "\services.txt"
Global $g_sTypesFile = $g_sBase & "\types.ini"

If Not FileExists($g_sImgFolder) Then DirCreate($g_sImgFolder)

; ---------- Session ----------------------------------------------------------
Global $g_sCurrentUser = ""
Global $g_sCurrentRole = ""

; ---------- Handles — Composer -----------------------------------------------
Global $g_comboType, $g_inputObjet, $g_inputMsg
Global $g_inputImage, $g_btnBrowse, $g_inputSignature
Global $g_chkAll, $g_lvServices, $g_inputServiceFilter
Global $g_btnCheckAll, $g_btnUncheckAll
Global $g_btnSave, $g_btnSilenceToggle, $g_btnClear, $g_lblEtat
Global $g_aTypeIDs[0]
; État des coches de services (tableau maître)
Global $g_aServNames[0]
Global $g_aServChecked[0]
Global $g_sLastFilter = ""

; ---------- Handles — Utilisateurs ------------------------------------------
Global $g_lvUsers, $g_inputNewUser, $g_comboNewRole
Global $g_inputNewService, $g_inputNewPwd, $g_btnAddUser, $g_btnDelUser

; ---------- Handles — Historique --------------------------------------------
Global $g_editLog, $g_btnRefreshLog

; ---------- Handles — Configuration -----------------------------------------
Global $g_inputADServer, $g_inputADBase, $g_btnTestAD, $g_lblADStatus
Global $g_lvTypes, $g_inputTypeID, $g_inputTypeLabel, $g_inputTypeBannerLabel
Global $g_lblSwBg,     $g_btnPickBg
Global $g_lblSwText,   $g_btnPickText
Global $g_lblSwBanner, $g_btnPickBanner
Global $g_btnSaveType, $g_btnDelType, $g_btnLoadType
Global $g_iColBg = 0xE7F3FF, $g_iColText = 0x003087, $g_iColBanner = 0x0057B7

; =============================================================================
; POINT D'ENTRÉE  (pas de requête AD au démarrage)
; =============================================================================
_EnsureDefaultAdmin()
_InitTypesFile()
If Not _Login() Then Exit
_CreateMainGUI()

; =============================================================================
; GUI PRINCIPALE
; =============================================================================
Func _CreateMainGUI()
    Local $hGUI = GUICreate("MsgSrv - Messagerie interne", 660, 680)
    GUISetBkColor(0xF5F6FA)

    Local $lblUser = GUICtrlCreateLabel( _
        "Connecte : " & $g_sCurrentUser & "   Role : " & $g_sCurrentRole, 12, 8, 540, 16)
    GUICtrlSetFont($lblUser, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor($lblUser, 0x555555)

    Local $btnLogout = GUICtrlCreateButton("Deconnexion", 560, 4, 90, 22)
    GUICtrlSetFont($btnLogout, 8, 400, 0, "Segoe UI")

    Local $hTab = GUICtrlCreateTab(10, 30, 640, 624)
    GUICtrlSetFont($hTab, 9, 400, 0, "Segoe UI")

    GUICtrlCreateTabItem("   Composer   ")
    _BuildTabCompose()

    GUICtrlCreateTabItem("   Utilisateurs   ")
    _BuildTabUsers()

    GUICtrlCreateTabItem("   Historique   ")
    _BuildTabHistory()

    GUICtrlCreateTabItem("   Configuration   ")
    _BuildTabConfig()

    GUICtrlCreateTabItem("")
    GUISetState(@SW_SHOW, $hGUI)

    While True
        ; ---- Filtre services (détection de changement en temps réel) ----
        If GUICtrlGetState($g_inputServiceFilter) <> $GUI_HIDE Then
            Local $sF = GUICtrlRead($g_inputServiceFilter)
            If $sF <> $g_sLastFilter Then
                $g_sLastFilter = $sF
                _FilterServicesLV($sF)
            EndIf
        EndIf

        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE
                ExitLoop
            Case $btnLogout
                GUIDelete($hGUI)
                If _Login() Then _CreateMainGUI()
                Return

            ; Composer
            Case $g_btnSave
                _Sauvegarder()
            Case $g_btnSilenceToggle
                _ToggleSilencieux()
            Case $g_btnBrowse
                _ParcourirImage()
            Case $g_btnClear
                _ViderChamps()
            Case $g_chkAll
                _SyncServicesEtat()
            Case $g_btnCheckAll
                _SetAllServicesChecked(True)
            Case $g_btnUncheckAll
                _SetAllServicesChecked(False)

            ; Utilisateurs
            Case $g_btnAddUser
                _AjouterUtilisateur()
            Case $g_btnDelUser
                _SupprimerUtilisateur()

            ; Historique
            Case $g_btnRefreshLog
                _ChargerHistorique()

            ; Configuration
            Case $g_btnTestAD
                _TestADConnection()
            Case $g_btnPickBg
                $g_iColBg = _PickColor($g_iColBg)
                _MAJ_Swatch($g_lblSwBg, $g_iColBg)
            Case $g_btnPickText
                $g_iColText = _PickColor($g_iColText)
                _MAJ_Swatch($g_lblSwText, $g_iColText)
            Case $g_btnPickBanner
                $g_iColBanner = _PickColor($g_iColBanner)
                _MAJ_Swatch($g_lblSwBanner, $g_iColBanner)
            Case $g_btnLoadType
                _ChargerTypeForm()
            Case $g_btnSaveType
                _SauvegarderType()
            Case $g_btnDelType
                _SupprimerType()
        EndSwitch
    WEnd
    GUIDelete($hGUI)
EndFunc

; =============================================================================
; ONGLET 1 — COMPOSER
; =============================================================================
Func _BuildTabCompose()
    Local $y = 58

    ; Type d'alerte
    GUICtrlCreateLabel("Type d'alerte :", 22, $y, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_comboType = GUICtrlCreateCombo("", 146, $y, 170, 22, $CBS_DROPDOWNLIST)
    GUICtrlSetFont($g_comboType, 9, 400, 0, "Segoe UI")
    _LoadTypesCombo()

    ; Objet
    GUICtrlCreateLabel("Objet :", 22, $y + 34, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputObjet = GUICtrlCreateInput("", 146, $y + 32, 480, 22)
    GUICtrlSetFont($g_inputObjet, 9, 400, 0, "Segoe UI")

    ; Message
    GUICtrlCreateLabel("Message :", 22, $y + 68, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputMsg = GUICtrlCreateEdit("", 22, $y + 88, 612, 95, _
        BitOR($ES_MULTILINE, $ES_WANTRETURN, $WS_VSCROLL))
    GUICtrlSetFont($g_inputMsg, 9, 400, 0, "Segoe UI")

    ; Image
    GUICtrlCreateLabel("Image :", 22, $y + 196, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputImage = GUICtrlCreateInput("", 146, $y + 194, 342, 22)
    GUICtrlSetFont($g_inputImage, 9, 400, 0, "Segoe UI")
    $g_btnBrowse = GUICtrlCreateButton("Parcourir", 494, $y + 193, 140, 24)
    GUICtrlSetFont($g_btnBrowse, 9, 400, 0, "Segoe UI")

    ; Signature
    GUICtrlCreateLabel("Signature :", 22, $y + 230, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputSignature = GUICtrlCreateInput("Le service informatique", 146, $y + 228, 480, 22)
    GUICtrlSetFont($g_inputSignature, 9, 400, 0, "Segoe UI")

    ; ── Destinataires ───────────────────────────────────────────────────────
    GUICtrlCreateLabel("Destinataires", 22, $y + 264, 120, 18)
    GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x333333)

    ; Case "Tout le monde"
    $g_chkAll = GUICtrlCreateCheckbox("Tout le monde", 22, $y + 286, 155, 22)
    GUICtrlSetFont($g_chkAll, 9, 700, 0, "Segoe UI")
    GUICtrlSetState($g_chkAll, $GUI_CHECKED)

    ; Barre de filtre + boutons check/uncheck
    GUICtrlCreateLabel("Filtrer :", 22, $y + 316, 52, 20)
    GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x666666)
    $g_inputServiceFilter = GUICtrlCreateInput("", 76, $y + 314, 220, 22)
    GUICtrlSetFont($g_inputServiceFilter, 9, 400, 0, "Segoe UI")

    $g_btnCheckAll = GUICtrlCreateButton("Tout cocher", 306, $y + 313, 110, 24)
    GUICtrlSetFont($g_btnCheckAll, 8, 400, 0, "Segoe UI")
    $g_btnUncheckAll = GUICtrlCreateButton("Tout decocher", 422, $y + 313, 118, 24)
    GUICtrlSetFont($g_btnUncheckAll, 8, 400, 0, "Segoe UI")

    ; ListView des services avec coches
    $g_lvServices = GUICtrlCreateListView("", 22, $y + 341, 612, 175, _
        BitOR($LVS_REPORT, $LVS_NOCOLUMNHEADER, $LVS_SHOWSELALWAYS))
    GUICtrlSetFont($g_lvServices, 9, 400, 0, "Segoe UI")
    _GUICtrlListView_SetExtendedListViewStyle($g_lvServices, _
        BitOR($LVS_EX_CHECKBOXES, $LVS_EX_FULLROWSELECT))
    _GUICtrlListView_AddColumn($g_lvServices, "", 596)
    _PopulateServicesLV()

    ; Désactiver filtre et liste au départ (Tout le monde coché)
    _SyncServicesEtat()

    ; Boutons d'action
    Local $yBtn = $y + 528
    $g_btnSave          = GUICtrlCreateButton("Envoyer le message", 22, $yBtn, 185, 34)
    $g_btnSilenceToggle = GUICtrlCreateButton("Activer / Desactiver", 217, $yBtn, 185, 34)
    $g_btnClear         = GUICtrlCreateButton("Vider les champs", 412, $yBtn, 165, 34)
    GUICtrlSetFont($g_btnSave, 9, 700, 0, "Segoe UI")
    GUICtrlSetFont($g_btnSilenceToggle, 9, 400, 0, "Segoe UI")
    GUICtrlSetFont($g_btnClear, 9, 400, 0, "Segoe UI")

    If $g_sCurrentRole <> "admin" Then
        GUICtrlSetState($g_btnSilenceToggle, $GUI_DISABLE)
    EndIf

    $g_lblEtat = GUICtrlCreateLabel("", 22, $yBtn + 42, 612, 20)
    GUICtrlSetFont($g_lblEtat, 9, 400, 0, "Segoe UI")
    _MAJ_EtatAffichage()
    _ChargerMessage()
EndFunc

; Remplit $g_aServNames / $g_aServChecked depuis le fichier cache
; puis peuple le ListView
Func _PopulateServicesLV()
    Local $aServices = _GetServices()
    ReDim $g_aServNames[UBound($aServices)]
    ReDim $g_aServChecked[UBound($aServices)]
    For $i = 0 To UBound($aServices) - 1
        $g_aServNames[$i]   = $aServices[$i]
        $g_aServChecked[$i] = False
    Next
    _FilterServicesLV("")
EndFunc

; Reconstruit le ListView en appliquant le filtre textuel
Func _FilterServicesLV($sFilter)
    ; 1. Sauvegarder l'état des coches depuis la vue actuelle
    Local $nVisible = _GUICtrlListView_GetItemCount($g_lvServices)
    For $vi = 0 To $nVisible - 1
        Local $sName = _GUICtrlListView_GetItemText($g_lvServices, $vi)
        For $j = 0 To UBound($g_aServNames) - 1
            If $g_aServNames[$j] = $sName Then
                $g_aServChecked[$j] = _GUICtrlListView_GetItemChecked($g_lvServices, $vi)
                ExitLoop
            EndIf
        Next
    Next

    ; 2. Reconstruire avec filtre
    _GUICtrlListView_DeleteAllItems($g_lvServices)
    Local $sLow = StringLower($sFilter)
    For $j = 0 To UBound($g_aServNames) - 1
        If $sLow = "" Or StringInStr(StringLower($g_aServNames[$j]), $sLow) > 0 Then
            _GUICtrlListView_AddItem($g_lvServices, $g_aServNames[$j])
            Local $iIdx = _GUICtrlListView_GetItemCount($g_lvServices) - 1
            If $g_aServChecked[$j] Then
                _GUICtrlListView_SetItemChecked($g_lvServices, $iIdx, True)
            EndIf
        EndIf
    Next
EndFunc

; Coche ou décoche tous les services visibles + met à jour le tableau maître
Func _SetAllServicesChecked($bState)
    Local $n = _GUICtrlListView_GetItemCount($g_lvServices)
    For $i = 0 To $n - 1
        _GUICtrlListView_SetItemChecked($g_lvServices, $i, $bState)
        Local $sName = _GUICtrlListView_GetItemText($g_lvServices, $i)
        For $j = 0 To UBound($g_aServNames) - 1
            If $g_aServNames[$j] = $sName Then
                $g_aServChecked[$j] = $bState
                ExitLoop
            EndIf
        Next
    Next
EndFunc

; Active / désactive la liste selon l'état de "Tout le monde"
Func _SyncServicesEtat()
    Local $bAll = (GUICtrlRead($g_chkAll) = $GUI_CHECKED)
    If $bAll Then
        GUICtrlSetState($g_inputServiceFilter, $GUI_DISABLE)
        GUICtrlSetState($g_btnCheckAll,        $GUI_DISABLE)
        GUICtrlSetState($g_btnUncheckAll,      $GUI_DISABLE)
        GUICtrlSetState($g_lvServices,         $GUI_DISABLE)
    Else
        GUICtrlSetState($g_inputServiceFilter, $GUI_ENABLE)
        GUICtrlSetState($g_btnCheckAll,        $GUI_ENABLE)
        GUICtrlSetState($g_btnUncheckAll,      $GUI_ENABLE)
        GUICtrlSetState($g_lvServices,         $GUI_ENABLE)
    EndIf
EndFunc

; Renvoie la liste des services sélectionnés (ou "ALL")
Func _GetSelectedServices()
    If GUICtrlRead($g_chkAll) = $GUI_CHECKED Then Return "ALL"

    ; Synchroniser l'état depuis le LV avant de lire
    Local $n = _GUICtrlListView_GetItemCount($g_lvServices)
    For $vi = 0 To $n - 1
        Local $sName = _GUICtrlListView_GetItemText($g_lvServices, $vi)
        For $j = 0 To UBound($g_aServNames) - 1
            If $g_aServNames[$j] = $sName Then
                $g_aServChecked[$j] = _GUICtrlListView_GetItemChecked($g_lvServices, $vi)
                ExitLoop
            EndIf
        Next
    Next

    Local $sRes = ""
    For $j = 0 To UBound($g_aServNames) - 1
        If $g_aServChecked[$j] Then $sRes &= $g_aServNames[$j] & ";"
    Next
    Return StringTrimRight($sRes, 1)
EndFunc

; =============================================================================
; ONGLET 2 — UTILISATEURS
; =============================================================================
Func _BuildTabUsers()
    Local $y = 58
    If $g_sCurrentRole <> "admin" Then
        GUICtrlCreateLabel("Acces reserve aux administrateurs.", 22, $y + 20, 400, 24)
        GUICtrlSetFont(-1, 10, 400, 0, "Segoe UI")
        GUICtrlSetColor(-1, 0xCC0000)
        $g_lvUsers         = GUICtrlCreateDummy()
        $g_inputNewUser    = GUICtrlCreateDummy()
        $g_comboNewRole    = GUICtrlCreateDummy()
        $g_inputNewService = GUICtrlCreateDummy()
        $g_inputNewPwd     = GUICtrlCreateDummy()
        $g_btnAddUser      = GUICtrlCreateDummy()
        $g_btnDelUser      = GUICtrlCreateDummy()
        Return
    EndIf

    GUICtrlCreateLabel("Comptes autorises a utiliser la plateforme :", 22, $y, 400, 20)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")

    $g_lvUsers = GUICtrlCreateListView("Identifiant|Role|Service", 22, $y + 26, 612, 300, $LVS_REPORT)
    GUICtrlSetFont($g_lvUsers, 9, 400, 0, "Segoe UI")
    _GUICtrlListView_SetColumnWidth($g_lvUsers, 0, 220)
    _GUICtrlListView_SetColumnWidth($g_lvUsers, 1, 148)
    _GUICtrlListView_SetColumnWidth($g_lvUsers, 2, 237)
    _ChargerUtilisateurs()

    Local $yF = $y + 340

    GUICtrlCreateLabel("Identifiant :", 22, $yF, 110, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputNewUser = GUICtrlCreateInput("", 138, $yF - 2, 175, 22)
    GUICtrlSetFont($g_inputNewUser, 9, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("Role :", 330, $yF, 55, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_comboNewRole = GUICtrlCreateCombo("communication", 390, $yF - 2, 130, 22, $CBS_DROPDOWNLIST)
    GUICtrlSetData($g_comboNewRole, "admin")
    GUICtrlSetFont($g_comboNewRole, 9, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("Service :", 22, $yF + 34, 110, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputNewService = GUICtrlCreateInput("", 138, $yF + 32, 175, 22)
    GUICtrlSetFont($g_inputNewService, 9, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("Mot de passe :", 22, $yF + 68, 110, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputNewPwd = GUICtrlCreateInput("", 138, $yF + 66, 175, 22, $ES_PASSWORD)
    GUICtrlSetFont($g_inputNewPwd, 9, 400, 0, "Segoe UI")

    $g_btnAddUser = GUICtrlCreateButton("Ajouter", 330, $yF + 58, 120, 30)
    GUICtrlSetFont($g_btnAddUser, 9, 400, 0, "Segoe UI")
    $g_btnDelUser = GUICtrlCreateButton("Supprimer la selection", 22, $yF + 108, 210, 30)
    GUICtrlSetFont($g_btnDelUser, 9, 400, 0, "Segoe UI")
EndFunc

; =============================================================================
; ONGLET 3 — HISTORIQUE
; =============================================================================
Func _BuildTabHistory()
    Local $y = 58
    GUICtrlCreateLabel("Journal des messages (antichronologique) :", 22, $y, 500, 20)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")
    $g_editLog = GUICtrlCreateEdit("", 22, $y + 26, 612, 528, _
        BitOR($ES_MULTILINE, $ES_READONLY, $WS_VSCROLL, $ES_AUTOVSCROLL))
    GUICtrlSetFont($g_editLog, 8, 400, 0, "Consolas")
    GUICtrlSetBkColor($g_editLog, 0x1E1E2E)
    GUICtrlSetColor($g_editLog, 0xCDD6F4)
    $g_btnRefreshLog = GUICtrlCreateButton("Rafraichir", 22, $y + 564, 130, 28)
    GUICtrlSetFont($g_btnRefreshLog, 9, 400, 0, "Segoe UI")
    _ChargerHistorique()
EndFunc

; =============================================================================
; ONGLET 4 — CONFIGURATION
; =============================================================================
Func _BuildTabConfig()
    Local $y = 58

    If $g_sCurrentRole <> "admin" Then
        GUICtrlCreateLabel("Acces reserve aux administrateurs.", 22, $y + 20, 400, 24)
        GUICtrlSetFont(-1, 10, 400, 0, "Segoe UI")
        GUICtrlSetColor(-1, 0xCC0000)
        $g_inputADServer       = GUICtrlCreateDummy()
        $g_inputADBase         = GUICtrlCreateDummy()
        $g_btnTestAD           = GUICtrlCreateDummy()
        $g_lblADStatus         = GUICtrlCreateDummy()
        $g_lvTypes             = GUICtrlCreateDummy()
        $g_inputTypeID         = GUICtrlCreateDummy()
        $g_inputTypeLabel      = GUICtrlCreateDummy()
        $g_inputTypeBannerLabel = GUICtrlCreateDummy()
        $g_lblSwBg             = GUICtrlCreateDummy()
        $g_btnPickBg           = GUICtrlCreateDummy()
        $g_lblSwText           = GUICtrlCreateDummy()
        $g_btnPickText         = GUICtrlCreateDummy()
        $g_lblSwBanner         = GUICtrlCreateDummy()
        $g_btnPickBanner       = GUICtrlCreateDummy()
        $g_btnSaveType         = GUICtrlCreateDummy()
        $g_btnDelType          = GUICtrlCreateDummy()
        $g_btnLoadType         = GUICtrlCreateDummy()
        Return
    EndIf

    ; ── Section Active Directory ────────────────────────────────────────────
    GUICtrlCreateLabel("Active Directory", 22, $y, 200, 18)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")

    GUICtrlCreateLabel("Serveur LDAP :", 22, $y + 24, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputADServer = GUICtrlCreateInput( _
        IniRead($g_sConfig, "ActiveDirectory", "Server", ""), 146, $y + 22, 300, 22)
    GUICtrlSetFont($g_inputADServer, 9, 400, 0, "Segoe UI")
    GUICtrlCreateLabel("(vide = auto via RootDSE)", 454, $y + 26, 190, 14)
    GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x999999)

    GUICtrlCreateLabel("Base DN :", 22, $y + 52, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputADBase = GUICtrlCreateInput( _
        IniRead($g_sConfig, "ActiveDirectory", "BaseDN", ""), 146, $y + 50, 300, 22)
    GUICtrlSetFont($g_inputADBase, 9, 400, 0, "Segoe UI")
    GUICtrlCreateLabel("(vide = auto)", 454, $y + 54, 140, 14)
    GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x999999)

    $g_btnTestAD = GUICtrlCreateButton("Tester et rafraichir les services", 22, $y + 82, 240, 28)
    GUICtrlSetFont($g_btnTestAD, 9, 400, 0, "Segoe UI")
    $g_lblADStatus = GUICtrlCreateLabel("", 270, $y + 88, 360, 16)
    GUICtrlSetFont($g_lblADStatus, 8, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("La liste des services est chargee uniquement via ce bouton (pas au demarrage).", _
        22, $y + 116, 600, 14)
    GUICtrlSetFont(-1, 8, 400, 2, "Segoe UI")
    GUICtrlSetColor(-1, 0x555555)

    ; ── Section Types d'alertes ─────────────────────────────────────────────
    GUICtrlCreateLabel("Types d'alertes", 22, $y + 140, 200, 18)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")

    $g_lvTypes = GUICtrlCreateListView("ID|Label affiche|Fond|Texte|Banniere", _
        22, $y + 162, 612, 165, BitOR($LVS_REPORT, $LVS_SINGLESEL))
    GUICtrlSetFont($g_lvTypes, 9, 400, 0, "Segoe UI")
    _GUICtrlListView_SetColumnWidth($g_lvTypes, 0, 110)
    _GUICtrlListView_SetColumnWidth($g_lvTypes, 1, 152)
    _GUICtrlListView_SetColumnWidth($g_lvTypes, 2, 110)
    _GUICtrlListView_SetColumnWidth($g_lvTypes, 3, 110)
    _GUICtrlListView_SetColumnWidth($g_lvTypes, 4, 110)
    _ChargerTypesLV()

    $g_btnLoadType = GUICtrlCreateButton("Charger la selection dans le formulaire", 22, $y + 334, 262, 24)
    GUICtrlSetFont($g_btnLoadType, 8, 400, 0, "Segoe UI")

    ; Formulaire type
    Local $yF = $y + 366

    GUICtrlCreateLabel("ID (interne) :", 22, $yF, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputTypeID = GUICtrlCreateInput("", 146, $yF - 2, 120, 22)
    GUICtrlSetFont($g_inputTypeID, 9, 400, 0, "Segoe UI")
    GUICtrlCreateLabel("ex: maintenance", 274, $yF + 2, 130, 14)
    GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x999999)

    GUICtrlCreateLabel("Label :", 22, $yF + 30, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputTypeLabel = GUICtrlCreateInput("", 146, $yF + 28, 200, 22)
    GUICtrlSetFont($g_inputTypeLabel, 9, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("Texte banniere :", 22, $yF + 60, 118, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_inputTypeBannerLabel = GUICtrlCreateInput("", 146, $yF + 58, 200, 22)
    GUICtrlSetFont($g_inputTypeBannerLabel, 9, 400, 0, "Segoe UI")
    GUICtrlCreateLabel("ex: Maintenance reseau", 354, $yF + 62, 200, 14)
    GUICtrlSetFont(-1, 8, 400, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x999999)

    ; Swatches couleur
    Local $yC = $yF + 92

    GUICtrlCreateLabel("Fond :", 22, $yC, 80, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_lblSwBg = GUICtrlCreateLabel("", 78, $yC + 1, 36, 18)
    GUICtrlSetBkColor($g_lblSwBg, $g_iColBg)
    $g_btnPickBg = GUICtrlCreateButton("...", 120, $yC - 1, 30, 22)
    GUICtrlSetFont($g_btnPickBg, 9, 700, 0, "Segoe UI")

    GUICtrlCreateLabel("Texte :", 170, $yC, 70, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_lblSwText = GUICtrlCreateLabel("", 226, $yC + 1, 36, 18)
    GUICtrlSetBkColor($g_lblSwText, $g_iColText)
    $g_btnPickText = GUICtrlCreateButton("...", 268, $yC - 1, 30, 22)
    GUICtrlSetFont($g_btnPickText, 9, 700, 0, "Segoe UI")

    GUICtrlCreateLabel("Banniere :", 318, $yC, 80, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    $g_lblSwBanner = GUICtrlCreateLabel("", 400, $yC + 1, 36, 18)
    GUICtrlSetBkColor($g_lblSwBanner, $g_iColBanner)
    $g_btnPickBanner = GUICtrlCreateButton("...", 442, $yC - 1, 30, 22)
    GUICtrlSetFont($g_btnPickBanner, 9, 700, 0, "Segoe UI")

    Local $yA = $yF + 122
    $g_btnSaveType = GUICtrlCreateButton("Enregistrer le type", 22, $yA, 180, 30)
    GUICtrlSetFont($g_btnSaveType, 9, 700, 0, "Segoe UI")
    $g_btnDelType = GUICtrlCreateButton("Supprimer la selection", 212, $yA, 200, 30)
    GUICtrlSetFont($g_btnDelType, 9, 400, 0, "Segoe UI")

    GUICtrlCreateLabel("Le combo Type d'alerte (onglet Composer) se met a jour automatiquement apres chaque modification.", _
        22, $yA + 38, 610, 14)
    GUICtrlSetFont(-1, 8, 400, 2, "Segoe UI")
    GUICtrlSetColor(-1, 0x555555)
EndFunc

; =============================================================================
; LOGIQUE — COMPOSER
; =============================================================================
Func _LoadTypesCombo()
    DllCall("user32.dll", "lresult", "SendMessage", _
        "hwnd", GUICtrlGetHandle($g_comboType), "uint", 0x014B, "wparam", 0, "lparam", 0)
    Local $aSecs = IniReadSectionNames($g_sTypesFile)
    If @error Then Return
    If $aSecs[0] = 0 Then Return
    ReDim $g_aTypeIDs[$aSecs[0]]
    Local $sAll = ""
    For $i = 1 To $aSecs[0]
        $g_aTypeIDs[$i - 1] = $aSecs[$i]
        $sAll &= ($i > 1 ? "|" : "") & $aSecs[$i]
    Next
    GUICtrlSetData($g_comboType, $sAll, $aSecs[1])
EndFunc

Func _GetSelectedTypeID()
    Local $sVal = GUICtrlRead($g_comboType)
    For $i = 0 To UBound($g_aTypeIDs) - 1
        If $g_aTypeIDs[$i] = $sVal Then Return $g_aTypeIDs[$i]
    Next
    Return $sVal
EndFunc

Func _ChargerMessage()
    If Not FileExists($g_sFichier) Then Return
    Local $sContenu = FileRead($g_sFichier)
    If $sContenu = "" Then Return
    Local $aLines = StringSplit($sContenu, @CRLF, 1)
    Local $sTypeID = "", $sObjet = "", $sMsg = "", $sImg = "", $sSig = "", $sTag = ""
    For $i = 1 To $aLines[0]
        Local $sLine = $aLines[$i]
        If StringLeft($sLine, 1) = "[" And StringRight($sLine, 1) = "]" Then
            $sTag = StringTrimLeft(StringTrimRight($sLine, 1), 1)
            If IniRead($g_sTypesFile, $sTag, "label", "") <> "" Then $sTypeID = $sTag
        Else
            Switch $sTag
                Case $sTypeID
                    If $sObjet = "" Then
                        $sObjet = $sLine
                    ElseIf $sLine <> "" Then
                        $sMsg &= $sLine & @CRLF
                    EndIf
                Case "image"
                    If $sImg = "" Then $sImg = $sLine
                Case "signature"
                    If $sSig = "" Then $sSig = $sLine
            EndSwitch
        EndIf
    Next
    ; CB_SELECTSTRING (0x014D) : sélectionne un item existant sans en ajouter
    If $sTypeID <> "" Then
        DllCall("user32.dll", "lresult", "SendMessage", _
            "hwnd",   GUICtrlGetHandle($g_comboType), _
            "uint",   0x014D, _
            "wparam", -1, _
            "str",    $sTypeID)
    EndIf
    GUICtrlSetData($g_inputObjet, $sObjet)
    GUICtrlSetData($g_inputMsg, StringStripWS($sMsg, 3))
    GUICtrlSetData($g_inputImage, $sImg)
    If $sSig <> "" Then GUICtrlSetData($g_inputSignature, $sSig)
EndFunc

Func _ParcourirImage()
    Local $sFile = FileOpenDialog("Selectionner une image", @ScriptDir, _
        "Images (*.jpg;*.jpeg;*.png;*.gif;*.bmp)", 1)
    If Not @error Then GUICtrlSetData($g_inputImage, $sFile)
EndFunc

Func _Sauvegarder()
    Local $sTypeID    = _GetSelectedTypeID()
    Local $sObjet     = StringStripWS(GUICtrlRead($g_inputObjet), 3)
    Local $sMsg       = GUICtrlRead($g_inputMsg)
    Local $sImagePath = StringStripWS(GUICtrlRead($g_inputImage), 3)
    Local $sSig       = StringStripWS(GUICtrlRead($g_inputSignature), 3)
    Local $sServices  = _GetSelectedServices()

    If $sObjet = "" Then
        MsgBox(48, "Champ manquant", "L'objet du message est obligatoire.")
        Return
    EndIf
    If $sServices = "" Then
        MsgBox(48, "Aucun destinataire", "Cochez au moins un service ou 'Tout le monde'.")
        Return
    EndIf

    Local $sImageFinal = ""
    If $sImagePath <> "" And FileExists($sImagePath) Then
        Local $sExt = "." & StringRight($sImagePath, StringLen($sImagePath) - StringInStr($sImagePath, ".", 0, -1))
        $sImageFinal = $g_sImgFolder & "\" & StringRegExpReplace(_WinAPI_CreateGUID(), "[{}\-]", "") & $sExt
        FileCopy($sImagePath, $sImageFinal, 1)
    ElseIf $sImagePath <> "" Then
        $sImageFinal = $sImagePath
    EndIf

    Local $sMsgUID = StringRegExpReplace(_WinAPI_CreateGUID(), "[{}\-]", "")
    Local $hFile   = FileOpen($g_sFichier, 2)
    If $hFile = -1 Then
        MsgBox(16, "Erreur", "Impossible d'ecrire dans " & $g_sFichier)
        Return
    EndIf
    FileWrite($hFile, "[" & $sTypeID & "]" & @CRLF & $sObjet & @CRLF & $sMsg)
    FileWrite($hFile, @CRLF & "[services]"  & @CRLF & $sServices)
    FileWrite($hFile, @CRLF & "[emetteur]"  & @CRLF & $g_sCurrentUser)
    If $sImageFinal <> "" Then
        FileWrite($hFile, @CRLF & "[image]" & @CRLF & $sImageFinal)
    EndIf
    If $sSig <> "" Then
        FileWrite($hFile, @CRLF & "[signature]" & @CRLF & $sSig)
    EndIf
    FileWrite($hFile, @CRLF & "[uuid]" & @CRLF & $sMsgUID)
    FileClose($hFile)

    Local $sTS  = @YEAR & "-" & @MON & "-" & @MDAY & " " & @HOUR & ":" & @MIN & ":" & @SEC
    Local $hLog = FileOpen($g_sLogFile, 1)
    If $hLog <> -1 Then
        FileWriteLine($hLog, $sTS & " | " & $g_sCurrentUser & " [" & $g_sCurrentRole & "]" & _
            " | [" & $sTypeID & "] " & $sObjet & " | Dest: " & $sServices & " | UUID: " & $sMsgUID)
        FileClose($hLog)
    EndIf
    MsgBox(64, "Message envoye", "Diffuse avec succes." & @CRLF & "Destinataires : " & $sServices)
EndFunc

Func _ViderChamps()
    _LoadTypesCombo()
    GUICtrlSetData($g_inputObjet, "")
    GUICtrlSetData($g_inputMsg, "")
    GUICtrlSetData($g_inputImage, "")
    GUICtrlSetData($g_inputSignature, "Le service informatique")
    GUICtrlSetState($g_chkAll, $GUI_CHECKED)
    GUICtrlSetData($g_inputServiceFilter, "")
    $g_sLastFilter = ""
    _SetAllServicesChecked(False)
    _SyncServicesEtat()
EndFunc

Func _ToggleSilencieux()
    Local $s = IniRead($g_sConfig, "Parametres", "Silencieux", "0")
    Local $n = ($s = "1") ? "0" : "1"
    IniWrite($g_sConfig, "Parametres", "Silencieux", $n)
    MsgBox(64, "Etat modifie", "Affichage " & (($n = "1") ? "desactive." : "reactive."))
    _MAJ_EtatAffichage()
EndFunc

Func _MAJ_EtatAffichage()
    Local $s = IniRead($g_sConfig, "Parametres", "Silencieux", "0")
    GUICtrlSetData($g_lblEtat, ($s = "1") ? "Messages desactives" : "Messages actives")
    GUICtrlSetColor($g_lblEtat, ($s = "1") ? 0xCC0000 : 0x007700)
EndFunc

; =============================================================================
; LOGIQUE — UTILISATEURS
; =============================================================================
Func _ChargerUtilisateurs()
    _GUICtrlListView_DeleteAllItems($g_lvUsers)
    Local $aSec = IniReadSectionNames($g_sUsersFile)
    If @error Then Return
    For $i = 1 To $aSec[0]
        GUICtrlCreateListViewItem($aSec[$i] & "|" & _
            IniRead($g_sUsersFile, $aSec[$i], "role", "") & "|" & _
            IniRead($g_sUsersFile, $aSec[$i], "service", ""), $g_lvUsers)
    Next
EndFunc

Func _AjouterUtilisateur()
    Local $sUser = StringStripWS(GUICtrlRead($g_inputNewUser), 3)
    Local $sPwd  = GUICtrlRead($g_inputNewPwd)
    If $sUser = "" Or $sPwd = "" Then
        MsgBox(48, "Champs manquants", "Identifiant et mot de passe obligatoires.")
        Return
    EndIf
    If StringLen($sPwd) < 6 Then
        MsgBox(48, "Mot de passe court", "Minimum 6 caracteres.")
        Return
    EndIf
    IniWrite($g_sUsersFile, $sUser, "role",     GUICtrlRead($g_comboNewRole))
    IniWrite($g_sUsersFile, $sUser, "service",  StringStripWS(GUICtrlRead($g_inputNewService), 3))
    IniWrite($g_sUsersFile, $sUser, "password", _HashPwd($sPwd))
    GUICtrlSetData($g_inputNewUser,    "")
    GUICtrlSetData($g_inputNewPwd,     "")
    GUICtrlSetData($g_inputNewService, "")
    _ChargerUtilisateurs()
    MsgBox(64, "OK", "Utilisateur '" & $sUser & "' cree.")
EndFunc

Func _SupprimerUtilisateur()
    Local $iSel = _GUICtrlListView_GetSelectedIndices($g_lvUsers)
    If $iSel = "" Then
        MsgBox(48, "Aucune selection", "Selectionnez un utilisateur.")
        Return
    EndIf
    Local $sUser = _GUICtrlListView_GetItemText($g_lvUsers, Int($iSel), 0)
    If $sUser = $g_sCurrentUser Then
        MsgBox(48, "Refuse", "Vous ne pouvez pas supprimer votre propre compte.")
        Return
    EndIf
    If MsgBox(36, "Confirmation", "Supprimer '" & $sUser & "' ?") = 6 Then
        IniDelete($g_sUsersFile, $sUser)
        _ChargerUtilisateurs()
    EndIf
EndFunc

; =============================================================================
; LOGIQUE — HISTORIQUE
; =============================================================================
Func _ChargerHistorique()
    If Not FileExists($g_sLogFile) Then
        GUICtrlSetData($g_editLog, "Aucun historique.")
        Return
    EndIf
    Local $aLines = StringSplit(StringStripWS(FileRead($g_sLogFile), 3), @LF, 2)
    Local $sInv = ""
    For $i = UBound($aLines) - 1 To 0 Step -1
        Local $sL = StringStripWS($aLines[$i], 2)
        If $sL <> "" Then $sInv &= $sL & @CRLF
    Next
    GUICtrlSetData($g_editLog, $sInv)
EndFunc

; =============================================================================
; LOGIQUE — CONFIGURATION AD
; =============================================================================
Func _TestADConnection()
    IniWrite($g_sConfig, "ActiveDirectory", "Server", StringStripWS(GUICtrlRead($g_inputADServer), 3))
    IniWrite($g_sConfig, "ActiveDirectory", "BaseDN", StringStripWS(GUICtrlRead($g_inputADBase), 3))
    GUICtrlSetData($g_lblADStatus, "Connexion en cours...")
    GUICtrlSetColor($g_lblADStatus, 0x888888)

    Local $aServices = _ADGetDepartments()
    If UBound($aServices) > 0 Then
        Local $hF = FileOpen($g_sServFile, 2)
        For $i = 0 To UBound($aServices) - 1
            FileWriteLine($hF, $aServices[$i])
        Next
        FileClose($hF)
        ; Recharger la liste des services dans le composer
        _PopulateServicesLV()
        GUICtrlSetData($g_lblADStatus, UBound($aServices) & " services trouves et enregistres.")
        GUICtrlSetColor($g_lblADStatus, 0x007700)
    Else
        GUICtrlSetData($g_lblADStatus, "Aucun resultat. Verifiez les parametres AD.")
        GUICtrlSetColor($g_lblADStatus, 0xCC0000)
    EndIf
EndFunc

; =============================================================================
; LOGIQUE — TYPES D'ALERTES
; =============================================================================
Func _ChargerTypesLV()
    _GUICtrlListView_DeleteAllItems($g_lvTypes)
    Local $aSecs = IniReadSectionNames($g_sTypesFile)
    If @error Then Return
    For $i = 1 To $aSecs[0]
        Local $s = $aSecs[$i]
        GUICtrlCreateListViewItem($s & "|" & _
            IniRead($g_sTypesFile, $s, "label", $s) & "|" & _
            "#" & IniRead($g_sTypesFile, $s, "bgColor", "FFFFFF") & "|" & _
            "#" & IniRead($g_sTypesFile, $s, "textColor", "000000") & "|" & _
            "#" & IniRead($g_sTypesFile, $s, "bannerColor", "333333"), $g_lvTypes)
    Next
EndFunc

Func _ChargerTypeForm()
    Local $iSel = _GUICtrlListView_GetSelectedIndices($g_lvTypes)
    If $iSel = "" Then
        MsgBox(48, "Aucune selection", "Cliquez sur un type dans la liste.")
        Return
    EndIf
    Local $sID = _GUICtrlListView_GetItemText($g_lvTypes, Int($iSel), 0)
    GUICtrlSetData($g_inputTypeID,          $sID)
    GUICtrlSetData($g_inputTypeLabel,       IniRead($g_sTypesFile, $sID, "label",       $sID))
    GUICtrlSetData($g_inputTypeBannerLabel, IniRead($g_sTypesFile, $sID, "bannerLabel", $sID))
    $g_iColBg     = Int("0x" & IniRead($g_sTypesFile, $sID, "bgColor",     "E7F3FF"))
    $g_iColText   = Int("0x" & IniRead($g_sTypesFile, $sID, "textColor",   "003087"))
    $g_iColBanner = Int("0x" & IniRead($g_sTypesFile, $sID, "bannerColor", "0057B7"))
    _MAJ_Swatch($g_lblSwBg,     $g_iColBg)
    _MAJ_Swatch($g_lblSwText,   $g_iColText)
    _MAJ_Swatch($g_lblSwBanner, $g_iColBanner)
EndFunc

Func _SauvegarderType()
    Local $sID     = StringStripWS(StringLower(GUICtrlRead($g_inputTypeID)), 3)
    Local $sLabel  = StringStripWS(GUICtrlRead($g_inputTypeLabel), 3)
    Local $sBanner = StringStripWS(GUICtrlRead($g_inputTypeBannerLabel), 3)
    If $sID = "" Then
        MsgBox(48, "Champ manquant", "L'ID est obligatoire.")
        Return
    EndIf
    If $sLabel = "" Then
        MsgBox(48, "Champ manquant", "Le label est obligatoire.")
        Return
    EndIf
    Local $aReserved = StringSplit("services|emetteur|image|signature|uuid", "|", 2)
    For $i = 0 To UBound($aReserved) - 1
        If $sID = $aReserved[$i] Then
            MsgBox(48, "ID reserve", "'" & $sID & "' est reserve. Choisissez un autre ID.")
            Return
        EndIf
    Next
    IniWrite($g_sTypesFile, $sID, "label",       $sLabel)
    IniWrite($g_sTypesFile, $sID, "bannerLabel",  ($sBanner <> "" ? $sBanner : $sLabel))
    IniWrite($g_sTypesFile, $sID, "bgColor",      _ColorToHex($g_iColBg))
    IniWrite($g_sTypesFile, $sID, "textColor",    _ColorToHex($g_iColText))
    IniWrite($g_sTypesFile, $sID, "bannerColor",  _ColorToHex($g_iColBanner))
    _ChargerTypesLV()
    _LoadTypesCombo()
    MsgBox(64, "Type enregistre", "Le type '" & $sID & "' a ete sauvegarde.")
EndFunc

Func _SupprimerType()
    Local $iSel = _GUICtrlListView_GetSelectedIndices($g_lvTypes)
    If $iSel = "" Then
        MsgBox(48, "Aucune selection", "Selectionnez un type.")
        Return
    EndIf
    Local $sID = _GUICtrlListView_GetItemText($g_lvTypes, Int($iSel), 0)
    If MsgBox(36, "Confirmation", "Supprimer le type '" & $sID & "' ?") = 6 Then
        IniDelete($g_sTypesFile, $sID)
        _ChargerTypesLV()
        _LoadTypesCombo()
    EndIf
EndFunc

; =============================================================================
; UTILITAIRES COULEUR
; =============================================================================
Func _PickColor($iCurrentRGB)
    Local $iResult = _ChooseColor(0, _SwapRB($iCurrentRGB), 2)
    If $iResult = -1 Then Return $iCurrentRGB
    Return _SwapRB($iResult)
EndFunc

Func _MAJ_Swatch($hCtrl, $iColorRGB)
    GUICtrlSetBkColor($hCtrl, $iColorRGB)
EndFunc

Func _ColorToHex($iRGB)
    Return StringUpper(StringRight("000000" & Hex($iRGB, 6), 6))
EndFunc

Func _SwapRB($iColor)
    Local $r = BitShift(BitAND($iColor, 0xFF0000), 16)
    Local $g = BitShift(BitAND($iColor, 0x00FF00), 8)
    Local $b = BitAND($iColor, 0x0000FF)
    Return BitOR(BitShift($b, -16), BitShift($g, -8), $r)
EndFunc

; =============================================================================
; SERVICES (lecture depuis cache — PAS d'appel AD automatique)
; =============================================================================
Func _GetServices()
    If FileExists($g_sServFile) Then
        Local $a = FileReadToArray($g_sServFile)
        If Not @error And UBound($a) > 0 Then Return $a
    EndIf
    Return StringSplit("Communication|Direction|DSI|Juridique|Logistique|RH", "|", 2)
EndFunc

Func _ADGetDepartments()
    Local $aRes[0]
    Local $oErr = ObjEvent("AutoIt.Error", "_ADErrHandler")
    Local $sServer = IniRead($g_sConfig, "ActiveDirectory", "Server", "")
    Local $sBaseDN = IniRead($g_sConfig, "ActiveDirectory", "BaseDN", "")
    Local $sRootURL = "LDAP://" & ($sServer <> "" ? $sServer & "/" : "") & "RootDSE"

    Local $oRoot = ObjGet($sRootURL)
    If @error Or Not IsObj($oRoot) Then Return $aRes

    If $sBaseDN = "" Then
        $sBaseDN = $oRoot.defaultNamingContext
        If @error Or $sBaseDN = "" Then Return $aRes
    EndIf

    Local $sBase = "LDAP://" & ($sServer <> "" ? $sServer & "/" : "") & $sBaseDN
    Local $oConn = ObjCreate("ADODB.Connection")
    If @error Or Not IsObj($oConn) Then Return $aRes
    Local $oCmd = ObjCreate("ADODB.Command")
    If @error Or Not IsObj($oCmd) Then Return $aRes

    $oConn.Provider = "ADsDSOObject"
    $oConn.Open("Active Directory Provider")
    If @error Then Return $aRes

    $oCmd.ActiveConnection = $oConn
    $oCmd.CommandText = "<" & $sBase & ">;" & _
        "(&(objectClass=user)(objectCategory=person)(department=*));department;subtree"
    $oCmd.Properties("Page Size") = 1000
    $oCmd.Properties("Sort On")   = "department"

    Local $oRS = $oCmd.Execute()
    If @error Or Not IsObj($oRS) Then
        $oConn.Close()
        Return $aRes
    EndIf

    Local $aTemp[300], $n = 0, $sLast = ""
    $oRS.MoveFirst()
    While Not $oRS.EOF And $n < 300
        Local $sDept = $oRS.Fields("department").Value
        If @error Then ExitLoop
        If $sDept <> $sLast And $sDept <> "" Then
            $aTemp[$n] = $sDept
            $n += 1
            $sLast = $sDept
        EndIf
        $oRS.MoveNext()
    WEnd
    $oRS.Close()
    $oConn.Close()
    ReDim $aTemp[$n]
    Return $aTemp
EndFunc

Func _ADErrHandler()
EndFunc

; =============================================================================
; AUTHENTIFICATION & INIT
; =============================================================================
Func _EnsureDefaultAdmin()
    If Not FileExists($g_sUsersFile) Then
        IniWrite($g_sUsersFile, "admin", "role",     "admin")
        IniWrite($g_sUsersFile, "admin", "service",  "Informatique")
        IniWrite($g_sUsersFile, "admin", "password", _HashPwd("admin"))
        MsgBox(64, "Premier lancement", _
            "Compte cree : admin / admin" & @CRLF & _
            "Changez ce mot de passe dans l'onglet Utilisateurs.")
    EndIf
EndFunc

Func _InitTypesFile()
    If FileExists($g_sTypesFile) Then Return
    IniWrite($g_sTypesFile, "info",    "label",       "Information")
    IniWrite($g_sTypesFile, "info",    "bannerLabel",  "Information")
    IniWrite($g_sTypesFile, "info",    "bgColor",      "E7F3FF")
    IniWrite($g_sTypesFile, "info",    "textColor",    "003087")
    IniWrite($g_sTypesFile, "info",    "bannerColor",  "0057B7")
    IniWrite($g_sTypesFile, "alerte",  "label",       "Alerte")
    IniWrite($g_sTypesFile, "alerte",  "bannerLabel",  "Alerte")
    IniWrite($g_sTypesFile, "alerte",  "bgColor",      "FFF8E1")
    IniWrite($g_sTypesFile, "alerte",  "textColor",    "6B4000")
    IniWrite($g_sTypesFile, "alerte",  "bannerColor",  "E67E00")
    IniWrite($g_sTypesFile, "urgence", "label",       "URGENCE")
    IniWrite($g_sTypesFile, "urgence", "bannerLabel",  "URGENCE")
    IniWrite($g_sTypesFile, "urgence", "bgColor",      "FFF0F0")
    IniWrite($g_sTypesFile, "urgence", "textColor",    "7A0000")
    IniWrite($g_sTypesFile, "urgence", "bannerColor",  "CC0000")
EndFunc

Func _Login()
    Local $hDlg   = GUICreate("Connexion - MsgSrv", 320, 180, -1, -1)
    GUISetBkColor(0xF5F6FA)
    GUICtrlCreateLabel("Connexion a la plateforme de messagerie interne", 10, 15, 300, 18)
    GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x003087)
    GUICtrlCreateLabel("Identifiant :", 20, 52, 90, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    Local $iU = GUICtrlCreateInput(@UserName, 120, 50, 175, 22)
    GUICtrlSetFont($iU, 9, 400, 0, "Segoe UI")
    GUICtrlCreateLabel("Mot de passe :", 20, 86, 90, 20)
    GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
    Local $iP = GUICtrlCreateInput("", 120, 84, 175, 22, $ES_PASSWORD)
    GUICtrlSetFont($iP, 9, 400, 0, "Segoe UI")
    Local $btnOK  = GUICtrlCreateButton("Connexion", 80, 124, 120, 30)
    GUICtrlSetFont($btnOK, 9, 700, 0, "Segoe UI")
    Local $btnAnn = GUICtrlCreateButton("Annuler", 215, 124, 80, 30)
    GUICtrlSetFont($btnAnn, 9, 400, 0, "Segoe UI")
    GUISetState(@SW_SHOW, $hDlg)

    Local $bOK = False
    While True
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnAnn
                ExitLoop
            Case $btnOK
                Local $sU = StringStripWS(GUICtrlRead($iU), 3)
                Local $sP = GUICtrlRead($iP)
                Local $sH = IniRead($g_sUsersFile, $sU, "password", "")
                Local $sR = IniRead($g_sUsersFile, $sU, "role", "")
                If $sH = "" Then
                    MsgBox(48, "Erreur", "Identifiant inconnu.")
                ElseIf $sH <> _HashPwd($sP) Then
                    MsgBox(48, "Erreur", "Mot de passe incorrect.")
                Else
                    $g_sCurrentUser = $sU
                    $g_sCurrentRole = $sR
                    $bOK = True
                    ExitLoop
                EndIf
        EndSwitch
    WEnd
    GUIDelete($hDlg)
    Return $bOK
EndFunc

Func _HashPwd($s)
    _Crypt_Startup()
    Local $h = _Crypt_HashData($s, $CALG_SHA_256)
    _Crypt_Shutdown()
    Return StringLower($h)
EndFunc
