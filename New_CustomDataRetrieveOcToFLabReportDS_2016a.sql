Testing:
/****** Object:  StoredProcedure [Custom].[Data_RetrieveOcToFLabReportDS]    Script Date: 1/4/2016 4:06:05 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [Custom].[Data_RetrieveOcToFLabReportDS]  
(  
	@labReportRequestId uniqueidentifier
)
AS  

-- Variables for List Iteration
DECLARE @rowCount int
DECLARE @rowMax int

DECLARE @myLabReportRequestTable table(
Id uniqueidentifier, CaseNum varchar(50), RecordNum smallint, AmendedSummary varchar(max))
INSERT INTO @myLabReportRequestTable
SELECT TOP 1 Id, CaseNum, RecordNum, AmendedSummary FROM dbo.LabReportRequest WHERE 
Id = @labReportRequestId

-- CaseNum variable for old code:
DECLARE @CaseNum varchar(50)
SET @CaseNum = (SELECT CaseNum FROM @myLabReportRequestTable)

-- Case Record's Evidence Exam listing in table form:
DECLARE @myCREvidenceExamTable table(
EvidenceExamId int, CaseNum varchar(50), RecordNum smallint, RelatedCaseNum varchar(50),
SubmissionCaseNum varchar(50), SubmissionNum smallint, EvidenceSubmissionID int,
EvidenceType char(1), EvidenceNum varchar(15), AgencyEvidenceID varchar(15), CustomDescription varchar(2000), ExamTypeCode varchar(8), 
ExamType varchar(50), Verified bit
)
INSERT INTO @myCREvidenceExamTable
SELECT
	CREE.CaseEvidenceExamID as [EvidenceExamId],
	CRE.CaseFSLabNum as [CaseNum],
	CRE.CaseID as [RecordNum],
	CRE.FSLabNum as [RelatedCaseNum],
	CRE.FSLabNum as [SubmissionCaseNum],
	CRE.SubmissionNum as [SubmissionNum],
	ESUB.EvidenceSubmissionID as [EvidenceSubmissionID],
	ESUB.EvidenceType,
	ESUB.EvidenceID as [EvidenceNum],
	ESUB.AgencyEvidenceID,
	CRE.[Description] as [CustomDescription],
	CREE.ExamTypeCode,
	ET.ExamTypeDescription as [ExamType],
	ESUB.Verified
FROM CaseEvidenceExam CREE
INNER JOIN CaseEvidence CRE ON CREE.CaseEvidenceID = CRE.CaseEvidenceID
INNER JOIN EvidenceSubmission ESUB ON 
	CRE.FSLabNum = ESUB.FSLabNum AND CRE.SubmissionNum = ESUB.SubmissionNum AND 
	CRE.EvidenceType = ESUB.EvidenceType AND CRE.EvidenceID = ESUB.EvidenceID 
INNER JOIN @myLabReportRequestTable CR ON CRE.CaseFSLabNum = CR.CaseNum AND CRE.CaseID = CR.RecordNum
INNER JOIN ExamType ET ON CREE.ExamTypeCode = ET.ExamTypeCode
LEFT JOIN Employee E ON CREE.AnalystId = E.EmployeeID

-- Related Cases (ordered)
DECLARE @RC table(
	CaseNum varchar(50), seq int IDENTITY(1,1))
	
-- Related Submissions (ordered)
DECLARE @RSUB table(
    CaseNum varchar(50),
    SubNum smallint,
    seq int IDENTITY(1,1))
    
-- Insert Primary Case, Submissions
INSERT INTO @RC(CaseNum) SELECT @CaseNum
INSERT INTO @RSUB (CaseNum, SubNum)
SELECT FSLabNum, SubmissionNum FROM Submission
WHERE FSLabNum = @CaseNum ORDER BY SubmissionNum  

-- Insert Related Cases, Submissions by evidence assigned to Case Records
INSERT INTO @RC (CaseNum)
SELECT DISTINCT FSLabNum FROM CaseEvidence CE
WHERE CaseFSLabNum = @CaseNum AND FSLabNum <> @CaseNum
ORDER BY FSLabNum
INSERT INTO @RSUB (CaseNum, SubNum)
SELECT DISTINCT FSLabNum, SubmissionNum
FROM CaseEvidence CE
WHERE CaseFSLabNum = @CaseNum AND FSLabNum <> @CaseNum
ORDER BY FSLabNum, SubmissionNum

-- CC Officer List Table, processing, and Final String Variable
-- Carbon Copy Officer Table:
DECLARE @myCCOfficer table(RowNum int Primary Key IDENTITY(1,1), 
CaseNum varchar(50), RecordNum smallint, OfficerID int, ReportName varchar(255), 
Title varchar(35), AgencyLocationName varchar(100), Address1 varchar(100), FormattedAddress1 varchar(128), 
Address2 varchar(100), FormattedAddress2 varchar(128), City varchar(50), FormattedCity varchar(64), 
[State] varchar(2), FormattedState varchar(4), Zip varchar(11), FormattedZip varchar(16),
ZipLast4 varchar(4), FormattedZipExt varchar(8))
INSERT INTO @myCCOfficer
SELECT DISTINCT
mLRR.CaseNum,
mLRR.RecordNum,
O.OfficerID,
[dbo].[GetFormattedReportName] (O.Title, O.FirstName, O.MiddleName, O.LastName, O.Suffix) AS [ReportName],
O.Title,
AL.AgencyLocationName,
A.Address1,
Case WHEN (A.Address1 IS NULL OR A.Address1 = '') THEN '' ELSE (A.Address1 + ' ') END AS [FormattedAddress1],
A.Address2,
Case WHEN (A.Address2 IS NULL OR A.Address2 = '') THEN '' ELSE (A.Address2 + ' ') END AS [FormattedAddress2],
A.City,
Case WHEN (A.City IS NULL OR A.City = '') THEN '' ELSE (A.City + ', ') END AS [FormattedCity],
A.[State],
Case WHEN (A.[State] IS NULL OR A.[State] = '') THEN '' ELSE (A.[State] + ' ') END AS [FormattedState],
A.Zip,
Case WHEN (A.Zip IS NULL OR A.Zip = '') THEN '' ELSE (A.Zip) END AS [FormattedZip],
A.ZipLast4,
Case WHEN ((A.ZipLast4 IS NULL OR LTRIM(RTRIM(A.ZipLast4)) = '') OR (A.Zip IS NULL OR A.Zip = '')) THEN '' ELSE ('-'+A.ZipLast4) END AS [FormattedZipExt]
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestOfficer] AS LRRO ON mLRR.Id = LRRO.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum AND Sub.FSLabNum in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionOfficer] AS SO ON Sub.FSLabNum = SO.FSLabNum AND Sub.SubmissionNum = SO.SubmissionNum AND LRRO.OfficerID = SO.OfficerID
INNER JOIN [dbo].[Officer] AS O ON SO.OfficerId = O.OfficerId
INNER JOIN [dbo].[AgencyLocation] AS AL ON O.AgencyID = AL.AgencyLocationId
INNER JOIN [dbo].[AgencyLocationAddress] AS ALA ON AL.AgencyLocationId = ALA.AgencyId AND ALA.AddressTypeCode = 'M'
INNER JOIN [dbo].[Address] AS A ON ALA.AddressID = A.AddressID
WHERE LRRO.OfficerTypeCode = 'CC'
SET @rowCount = 1
SET @rowMax = (SELECT COUNT(*) FROM @myCCOfficer)
DECLARE @formattedCCOfficerSummary varchar(max)
SET @formattedCCOfficerSummary = ''
IF @rowMax > 0
WHILE(@rowCount <= @rowMax)
BEGIN
	CREATE TABLE #myCCOfficerRow(
	CaseNum varchar(50), RecordNum smallint, OfficerID int, ReportName varchar(255), 
	Title varchar(35), AgencyLocationName varchar(100), Address1 varchar(100), FormattedAddress1 varchar(128), 
	Address2 varchar(100), FormattedAddress2 varchar(128), City varchar(50), FormattedCity varchar(64), 
	[State] varchar(2), FormattedState varchar(4), Zip varchar(11), FormattedZip varchar(16),
	ZipLast4 varchar(4), FormattedZipExt varchar(8))
	INSERT INTO #myCCOfficerRow
	SELECT TOP 1
	CaseNum, RecordNum, OfficerID, ReportName, Title, AgencyLocationName, Address1, FormattedAddress1, 
	Address2, FormattedAddress2, City, FormattedCity, [State], FormattedState, Zip, FormattedZip, 
	ZipLast4, FormattedZipExt FROM @myCCOfficer WHERE RowNum = @rowCount
	SET 
	@formattedCCOfficerSummary = @formattedCCOfficerSummary + '1  -       ' + (SELECT ISNULL(ReportName, '') FROM #myCCOfficerRow) + CHAR(13)
	IF (SELECT ISNULL(LTRIM(RTRIM(Title)), '') FROM #myCCOfficerRow)!=''
	SET
	@formattedCCOfficerSummary = @formattedCCOfficerSummary + '            ' + (SELECT ISNULL(Title, '') FROM #myCCOfficerRow) + CHAR(13)
	IF (SELECT ISNULL(LTRIM(RTRIM(AgencyLocationName)), '') FROM #myCCOfficerRow)!=''
	SET
	@formattedCCOfficerSummary = @formattedCCOfficerSummary + '            ' + (SELECT ISNULL(AgencyLocationName, '') FROM #myCCOfficerRow) + CHAR(13)
	SET
	@formattedCCOfficerSummary = @formattedCCOfficerSummary + '            ' + 
	(SELECT ISNULL(FormattedAddress1, '') FROM #myCCOfficerRow) + (SELECT ISNULL(FormattedAddress2, '') FROM #myCCOfficerRow) + 
	(SELECT ISNULL(FormattedCity, '') FROM #myCCOfficerRow) + (SELECT ISNULL(FormattedState, '') FROM #myCCOfficerRow) + 
	(SELECT ISNULL(FormattedZip, '') FROM #myCCOfficerRow) +  (SELECT ISNULL(FormattedZipExt, '') FROM #myCCOfficerRow) + CHAR(13)
	
	SET @rowcount = @rowCount + 1
	DROP TABLE #myCCOfficerRow
END 


SELECT 'CaseRoot' Name, '' ParentName, 'CaseNum' KeyFields, '' ChildKeyFields, 1 Sort UNION
SELECT 'ToOfficerData', 'CaseRoot', 'ToOfficerSummary', 'CaseNum', 20 Sort UNION
SELECT 'ToAgencyData', 'CaseRoot', 'CaseNum|RecordNum|AgencyLocationId', 'CaseNum', 30 Sort UNION
SELECT 'LabReportDate', 'CaseRoot', 'CaseNum|RecordNum|LabReportCreatedDateTime', 'CaseNum', 31 Sort UNION
SELECT 'SubmissionAgencyCaseInfo', 'CaseRoot', 'SubmissionAgencyCaseID', 'CaseNum', 40 Sort UNION
SELECT 'CommunicationSummary', 'CaseRoot', 'CommunicationSummary', 'CaseNum', 50 Sort UNION
SELECT 'AgencyReferenceSummary', 'CaseRoot', 'AgencyNumberSummary', 'CaseNum', 60 Sort UNION
SELECT 'SubjectSummary', 'CaseRoot', 'ReportNameSummary', 'CaseNum', 70 Sort UNION
SELECT 'VictimSummary', 'CaseRoot', 'ReportNameSummary', 'CaseNum', 80 Sort UNION
SELECT 'DisciplineData', 'CaseRoot', 'OrganizationID', 'CaseNum', 90 Sort UNION
SELECT 'EvidenceList', 'CaseRoot', 'OriginCaseNum|SubmissionNum|EvidenceType|EvidenceNum', 'CaseNum', 100 Sort UNION
--SELECT 'CCOfficerList', 'CaseRoot', '', 'CaseNum', 110 Sort UNION
SELECT 'ResultStatement', 'CaseRoot', 'Id', 'CaseNum', 120 Sort UNION
SELECT 'ResultTableHeader', 'CaseRoot', 'CaseNum|RecordNum', 'CaseNum', 130 Sort UNION
SELECT 'ResultTable', 'ResultTableHeader', '', 'CaseNum|RecordNum', 131 Sort UNION
SELECT 'NoteTableHeader', 'CaseRoot', 'CaseNum|RecordNum', 'CaseNum', 140 Sort UNION
SELECT 'NoteTable', 'NoteTableHeader', '', 'CaseNum|RecordNum', 141 Sort UNION
SELECT 'AdditionalReportText', 'CaseRoot', 'CaseNum|RecordNum|ReportReturnTextCode', 'CaseNum', 150 Sort UNION
SELECT 'AssignedExaminerInfo', 'CaseRoot', 'CaseNum|RecordNum|ReportName', 'CaseNum', 160 Sort UNION
SELECT 'mLRR', 'CaseRoot', '', 'CaseNum', 9000 Sort ORDER BY Sort


-- CASE ROOT (my/THIS case; case number being called from; not related cases)
SELECT TOP 1
	mLRR.CaseNum as [OriginCaseNum],
	mLRR.RecordNum as [OriginRecordNum],
	FSLabNum as [CaseNum],
	FileOpenDate as [OpenDate],
	OffenseDate,
	C.FSLabStatusCode as [StatusCode],
	S.FSLabStatusDescription as [Status],
	Comments,
	StatementOfFacts,
	IsConfidential,
	Country.Name AS CrimeSceneCountry,
	State.Name AS CrimeSceneState,
	City.Name AS CrimeSceneCity,
	HasFlagBlue,
	@formattedCCOfficerSummary AS [FormattedCCOfficerSummary]
FROM [FSLab] C
INNER JOIN FSLabStatus AS S ON C.FSLabStatusCode = S.FSLabStatusCode
INNER JOIN @myLabReportRequestTable AS mLRR ON C.FSLabNum = mLRR.CaseNum
LEFT JOIN Country ON C.CrimeSceneCountry = Country.Code
LEFT JOIN City ON C.CrimeSceneCity = City.Code
LEFT JOIN State ON C.CrimeSceneState = State.Code
WHERE C.FSLabNum = @CaseNum


-- ToOfficerData
DECLARE @myToOfficerSummary varchar(max)
DECLARE @myToOfficerInfoTable table(CaseNum varchar(50), RecordNum smallint, ReportName varchar(255), OfficerID int,
DisplayName varchar(85), Title varchar(35), JobTitle varchar(35), Salutation varchar(35), BadgeNum varchar(10), 
AgencyID int, EmailAddress varchar(255), FaxNumber varchar(50), PhoneNumber varchar(50))
INSERT INTO @myToOfficerInfoTable
SELECT TOP 1 
mLRR.CaseNum,
mLRR.RecordNum,
[dbo].[GetFormattedReportName] (O.Title, O.FirstName, O.MiddleName, O.LastName, O.Suffix) AS [ReportName],
O.OfficerID,
O.DisplayName,
O.Title As [Title],
O.JobTitle,
O.Salutation,
O.BadgeNum,
O.AgencyID,
O.EmailAddress,
O.FaxNumber,
O.PhoneNumber
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestOfficer] AS LRRO ON mLRR.Id = LRRO.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum AND Sub.FSLabNum in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionOfficer] AS SO ON Sub.FSLabNum = SO.FSLabNum AND Sub.SubmissionNum = SO.SubmissionNum AND LRRO.OfficerID = SO.OfficerID
INNER JOIN [dbo].[Officer] AS O ON SO.OfficerId = O.OfficerId
WHERE LRRO.OfficerTypeCode = 'INV'
SET @myToOfficerSummary = (SELECT ReportName FROM @myToOfficerInfoTable)
IF (SELECT ISNULL(LTRIM(RTRIM(Title)), '') FROM @myToOfficerInfoTable)!=''
SET @myToOfficerSummary = @myToOfficerSummary + CHAR(13) + (SELECT Title FROM @myToOfficerInfoTable)
SELECT @CaseNum AS [CaseNum], ISNULL(LTRIM(RTRIM(@myToOfficerSummary)), '') AS [ToOfficerSummary]

-- ToAgencyData
DECLARE @myAgencyDataTable table(
CaseNum varchar(50), RecordNum smallint, AgencyLocationId int, AgencyLocationName varchar(100), BusinessName varchar(200), 
Address1 varchar(100), Address2 varchar(100), City varchar(50), County varchar(100), [State] varchar(2), 
Zip varchar(11), ZipLast4 varchar(4), Country varchar(100), FaxNumber varchar(50), PhoneNumber varchar(50), 
PhoneExt varchar(10))
INSERT INTO @myAgencyDataTable
SELECT TOP 1 
mLRR.CaseNum,
mLRR.RecordNum,
AL.AgencyLocationId,
AL.AgencyLocationName AS [AgencyLocationName],
A.BusinessName,
A.Address1,
A.Address2,
A.City,
A.County,
A.[State],
A.Zip,
A.ZipLast4,
A.Country,
A.FaxNumber,
A.PhoneNumber,
A.PhoneExt
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestAgency] AS LRRA ON mLRR.Id = LRRA.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionAgency] AS SA ON SA.FSLabNum = Sub.FSLabNum AND SA.SubmissionNum = Sub.SubmissionNum AND SA.AgencyID = LRRA.AgencyLocationId
INNER JOIN [dbo].[AgencyLocation] AS AL ON SA.AgencyID = AL.AgencyLocationId
INNER JOIN [dbo].[AgencyLocationAddress] AS ALA ON AL.AgencyLocationId = ALA.AgencyId AND ALA.AddressTypeCode = 'M'
INNER JOIN [dbo].[Address] AS A ON ALA.AddressID = A.AddressID
DECLARE @addressDescription varchar(512)
SET @addressDescription = ''
DECLARE @address1 varchar(100)
SET @address1 = (ISNULL((SELECT Address1 FROM @myAgencyDataTable), ''))
DECLARE @address2 varchar(100)
SET @address2 = (ISNULL((SELECT Address2 FROM @myAgencyDataTable), ''))
DECLARE @city varchar(100)
SET @city = (ISNULL((SELECT City FROM @myAgencyDataTable), ''))
DECLARE @state varchar(100)
SET @state = (ISNULL((SELECT [State] FROM @myAgencyDataTable), ''))
DECLARE @zipMain varchar(100)
SET @zipMain = (ISNULL((SELECT Zip FROM @myAgencyDataTable), ''))
DECLARE @zipExt varchar(100)
SET @zipExt = (ISNULL((SELECT ZipLast4 FROM @myAgencyDataTable), ''))
IF @address1 != '' SET @addressDescription = @addressDescription + @address1 + CHAR(10)
IF @address2 != '' SET @addressDescription = @addressDescription + @address2 + CHAR(10)
IF (@city != '') AND (@state != '') SET @addressDescription = @addressDescription + @city + ', ' + @state + ' '
IF @zipMain != '' SET @addressDescription = @addressDescription + @zipMain
IF (@zipMain != '') AND (@zipExt != '') SET @addressDescription = @addressDescription + '-' + @zipExt
SELECT *, @addressDescription AS [AddressDescription] FROM @myAgencyDataTable


-- Lab Report Date
DECLARE @dateNow datetime
SET @dateNow = GETDATE()
SELECT TOP 1
mLRR.CaseNum,
mLRR.RecordNum,
@dateNow AS [LabReportCreatedDateTime],
DATENAME(MONTH,@dateNow) + ' ' + DATENAME(DAY,@dateNow) + ', ' + DATENAME(YEAR,@dateNow) AS [FormattedLabReportCreatedDate]
FROM @myLabReportRequestTable AS mLRR


-- Submission Agency Case Info (table)
DECLARE @myTopAgencyCaseInfo table(
CaseNum varchar(50), RecordNum int, SubmissionAgencyCaseID int, SubmissionAgencyID int, AgencyCaseNum varchar(35), OffenseDate datetime)
INSERT INTO @myTopAgencyCaseInfo
SELECT TOP 1 
mLRR.CaseNum,
mLRR.RecordNum,
SAC.SubmissionAgencyCaseID,
SAC.SubmissionAgencyID,
SAC.CaseNum AS [AgencyCaseNum],
SAC.OffenseDate
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestAgency] AS LRRA ON mLRR.Id = LRRA.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionAgency] AS SA ON Sub.FSLabNum = SA.FSLabNum AND Sub.SubmissionNum = SA.SubmissionNum AND SA.IsPrimary = 1
INNER JOIN [dbo].[SubmissionAgencyCase] AS SAC ON SA.SubmissionAgencyID = SAC.SubmissionAgencyID
SELECT * FROM @myTopAgencyCaseInfo
DECLARE @topSubmissionAgencyCaseId int
SET @topSubmissionAgencyCaseId = (SELECT TOP 1 SubmissionAGencyCaseID FROM @myTopAgencyCaseInfo)


-- Communication Summary
DECLARE @myCommunicationSubXD table(
RowNum int Primary Key IDENTITY(1,1), CaseNum varchar(50), StrData varchar(max), IntData bigint, 
FltData float, DteData datetime, FormatttedDate varchar(50), BitData bit, GIdData uniqueidentifier)
INSERT INTO @myCommunicationSubXD
SELECT DISTINCT
mLRR.CaseNum, xdP.StrData, xdP.IntData, xdP.FltData, 
xdP.DteData, 
DATENAME(MONTH,xdP.DteData) + ' ' + DATENAME(DAY,xdP.DteData) + ', ' + DATENAME(YEAR,xdP.DteData) AS [FormattedDate],
xdP.BitData, xdP.GIdData
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN xd.ElementDef AS xdED ON xdED.Name = 'SUBMISSION_XP'
INNER JOIN [xd].[Element] AS xdE ON Sub.[guid] = xdE.EntityId AND xdED.Id = xdE.DefId
INNER JOIN [xd].[PropertyDef] AS xdPD ON xdPD.ElementDefId = xdED.Id AND xdPD.Name = 'DocumentDate'
INNER JOIN [xd].[Property] AS xdP ON xdP.DefId = xdPD.Id AND xdP.ElementId = xdE.Id
SET @rowCount = 1
SET @rowMax = (SELECT COUNT(*) FROM @myCommunicationSubXD)
DECLARE @communicationSummary varchar(max)
SET @communicationSummary = ''
IF @rowMax > 0
WHILE(@rowCount <= @rowMax)
BEGIN
	SET @communicationSummary = @communicationSummary + (SELECT FormatttedDate FROM @myCommunicationSubXD WHERE RowNum = @rowCount)
	IF (@rowCount < @rowMax)
	BEGIN
		SET @communicationSummary = @communicationSummary + '; '
	END
	SET @rowcount = @rowCount + 1
END
SELECT @CaseNum AS [CaseNum], @communicationSummary AS [CommunicationSummary]


-- Agency Reference Summary (all additional agency case numbers)
DECLARE @myOtherAgencyCaseInfo table(
CaseNum varchar(50), RecordNum smallint, SubmissinAgencyCaseId int, AgencyCaseNum varchar(35), IsNotPrimary bit)
INSERT INTO @myOtherAgencyCaseInfo
SELECT DISTINCT
mLRR.CaseNum,
mLRR.RecordNum,
SAC.SubmissionAgencyCaseID,
SAC.CaseNum AS [AgencyCaseNum],
0
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestAgency] AS LRRA ON mLRR.Id = LRRA.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum AND Sub.FSLabNum in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionAgency] AS SA ON Sub.FSLabNum = SA.FSLabNum AND LRRA.SubNum = SA.SubmissionNum AND LRRA.AgencyLocationId = SA.AgencyID
INNER JOIN [dbo].[SubmissionAgencyCase] AS SAC ON SA.SubmissionAgencyID = SAC.SubmissionAgencyID AND ((SAC.CaseNum IS NOT NULL) OR (SAC.CaseNum != '')) AND SAC.SubmissionAgencyCaseID != @topSubmissionAgencyCaseId
ORDER BY SAC.SubmissionAgencyCaseID
INSERT INTO @myOtherAgencyCaseInfo
SELECT DISTINCT
mLRR.CaseNum,
mLRR.RecordNum,
SAC.SubmissionAgencyCaseID,
SAC.CaseNum AS [AgencyCaseNum],
1
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum AND Sub.FSLabNum in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionAgency] AS SA ON Sub.FSLabNum = SA.FSLabNum AND Sub.SubmissionNum = SA.SubmissionNum AND SA.SubmissionAgencyTypeCode = 'CC'
INNER JOIN [dbo].[SubmissionAgencyCase] AS SAC ON SA.SubmissionAgencyID = SAC.SubmissionAgencyID AND ((SAC.CaseNum IS NOT NULL) OR (SAC.CaseNum != ''))
ORDER BY SAC.SubmissionAgencyCaseID
DECLARE @myDistinctOtherAgencyCaseInfo table( RowNum int Primary Key IDENTITY(1,1),
CaseNum varchar(50), RecordNum smallint, AgencyCaseNum varchar(35))
INSERT INTO @myDistinctOtherAgencyCaseInfo
SELECT CaseNum, RecordNum, AgencyCaseNum FROM
(SELECT 
mOACI.CaseNum, 
mOACI.RecordNum, 
mOACI.AgencyCaseNum, 
mOACI.IsNotPrimary,
MIN(mOACI.SubmissinAgencyCaseId) MinSACId 
FROM @myOtherAgencyCaseInfo AS mOACI
GROUP BY mOACI.CaseNum, mOACI.RecordNum, mOACI.AgencyCaseNum, mOACI.IsNotPrimary
) AS Data
ORDER BY Data.IsNotPrimary, Data.MinSACId
SET @rowCount = 1
SET @rowMax = (SELECT COUNT(*) FROM @myDistinctOtherAgencyCaseInfo)
DECLARE @agencyNumberSummary varchar(max)
SET @agencyNumberSummary = ''
IF @rowMax > 0
WHILE(@rowCount <= @rowMax)
BEGIN
	SET @agencyNumberSummary = @agencyNumberSummary + (SELECT AgencyCaseNum FROM @myDistinctOtherAgencyCaseInfo WHERE RowNum = @rowCount)
	IF (@rowCount < @rowMax)
	BEGIN
		SET @agencyNumberSummary = @agencyNumberSummary + '; '
	END
	SET @rowcount = @rowCount + 1
END
SELECT @CaseNum AS [CaseNum], @agencyNumberSummary AS [AgencyNumberSummary]


-- Subject Summary
DECLARE @mySubjectList table(
RowNum int Primary Key IDENTITY(1,1), SubjectId int, CaseNum varchar(50), ReportName varchar(255))
-- add POI List:
INSERT INTO @mySubjectList
SELECT DISTINCT 
P.PersonId, mLRR.CaseNum,
[dbo].[GetFormattedReportName] (P.Prefix, P.FirstName, P.MiddleName, P.LastName, P.Suffix) AS [ReportName]
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestPersonOfInterest] AS LRRP ON mLRR.Id = LRRP.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum--in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionPerson] AS SP ON  Sub.FSLabNum = SP.CaseNum AND Sub.SubmissionNum = SP.SubNum AND LRRP.PersonId = SP.PersonId AND SP.POITypeCode = 'S'
INNER JOIN [dbo].[Person] AS P ON SP.PersonId = P.PersonId
ORDER BY P.PersonId
-- add Business List:
INSERT INTO @mySubjectList 
SELECT DISTINCT 
B.BusinessId, mLRR.CaseNum,
B.BusinessName AS [ReportName]
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum--in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionBusiness] AS SB ON  Sub.FSLabNum = SB.CaseNum AND Sub.SubmissionNum = SB.SubNum AND SB.POITypeCode = 'S'
INNER JOIN [dbo].[Business] AS B ON SB.BusinessId = B.BusinessId
ORDER BY B.BusinessId
SET @rowCount = 1
SET @rowMax = (SELECT COUNT(*) FROM @mySubjectList)
DECLARE @subjectSummary varchar(max)
SET @subjectSummary = ''
IF @rowMax > 0
WHILE(@rowCount <= @rowMax)
BEGIN
	SET @subjectSummary = @subjectSummary + (SELECT ReportName FROM @mySubjectList WHERE RowNum = @rowCount)
	IF (@rowCount < @rowMax)
	BEGIN
		SET @subjectSummary = @subjectSummary + '; '
	END
	SET @rowcount = @rowCount + 1
END
-- display:
SELECT @CaseNum AS [CaseNum], @subjectSummary AS [ReportNameSummary]


-- Victim Summary
DECLARE @myVictimList table(
RowNum int Primary Key IDENTITY(1,1), VictimId int, CaseNum varchar(50), ReportName varchar(255))
-- add POI List:
INSERT INTO @myVictimList
SELECT DISTINCT 
P.PersonId, mLRR.CaseNum,
[dbo].[GetFormattedReportName] (P.Prefix, P.FirstName, P.MiddleName, P.LastName, P.Suffix) AS [ReportName]
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[LabReportRequestPersonOfInterest] AS LRRP ON mLRR.Id = LRRP.LabReportRequestId
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum--in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionPerson] AS SP ON  Sub.FSLabNum = SP.CaseNum AND Sub.SubmissionNum = SP.SubNum AND LRRP.PersonId = SP.PersonId AND SP.POITypeCode in('V','MP')
INNER JOIN [dbo].[Person] AS P ON SP.PersonId = P.PersonId
ORDER BY P.PersonId
-- add Business List:
INSERT INTO @myVictimList 
SELECT DISTINCT 
B.BusinessId, mLRR.CaseNum,
B.BusinessName AS [ReportName]
FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[Submission] AS Sub ON Sub.FSLabNum = mLRR.CaseNum--in(SELECT CaseNum FROM @RC)
INNER JOIN @myCREvidenceExamTable AS CRE ON Sub.FSLabNum = CRE.SubmissionCaseNum AND Sub.SubmissionNum = CRE.SubmissionNum
INNER JOIN [dbo].[SubmissionBusiness] AS SB ON  Sub.FSLabNum = SB.CaseNum AND Sub.SubmissionNum = SB.SubNum AND SB.POITypeCode in('V','MP')
INNER JOIN [dbo].[Business] AS B ON SB.BusinessId = B.BusinessId
ORDER BY B.BusinessId
SET @rowCount = 1
SET @rowMax = (SELECT COUNT(*) FROM @myVictimList)
DECLARE @victimSummary varchar(max)
SET @victimSummary = ''
IF @rowMax > 0
WHILE(@rowCount <= @rowMax)
BEGIN
	SET @victimSummary = @victimSummary + (SELECT ReportName FROM @myVictimList WHERE RowNum = @rowCount)
	IF (@rowCount < @rowMax)
	BEGIN
		SET @victimSummary = @victimSummary + '; '
	END
	SET @rowcount = @rowCount + 1
END
-- display:
SELECT @CaseNum AS [CaseNum], @victimSummary AS [ReportNameSummary]


-- Discipline Data
SELECT mLRR.CaseNum, mLRR.RecordNum, C.OrganizationID, O.OrganizationCode, O.OrganizationName FROM @myLabReportRequestTable AS mLRR
INNER JOIN [dbo].[Case] C ON mLRR.CaseNum = C.FSLabNum AND mLRR.RecordNum = C.CaseID
INNER JOIN [dbo].[Organization] O ON C.OrganizationID = O.OrganizationID


-- Evidence List
-- Temporary table to hold evidence list used in Case evidence section and Submission evidence section:
DECLARE @MyEvidence TABLE(
MySort varchar(255),
SortLevel int,
CaseNum varchar(50),
SubmissionNum smallint,
CurrentSubmissionNum smallint,
EvidenceType char(1),
EvidenceNum varchar(15),
[Description] varchar(2000),
Comments varchar(max),
StatusCode char(1),
[Status] varchar(35),
EmployeeID int,
LabID int,
SectionID int,
StorageAreaID int,
StorageLocationCode varchar(6),
LockboxID int, 
ExternalId varchar(32),
EvidenceIDSortKey bigint,
EvidenceSubmissionID int,
ParentId int,
Verified bit,
SubmitCarrierPackageId VARCHAR(50))
;WITH MyEvidence AS
(
	SELECT
		CONVERT(VARCHAR(255), RIGHT(CONVERT(VARCHAR, (ROW_NUMBER() OVER (ORDER BY EvidenceIDSortKey)+1000)),3)) as MySort,
		1 as SortLevel,
		E.FSLabNum as [CaseNum],
		ES2.SubmissionNum,
		E.CurrentSubmissionNum,
		E.EvidenceType,
		E.EvidenceID as [EvidenceNum],
		E.Description,
		E.Comments,
		ES.EvidenceStatusCode as [StatusCode],
		ES.EvidenceStatusDescription as [Status],
		E.CustodyEmployeeID as [EmployeeID],
		E.CustodyLocationID as [LabID],
		E.CustodyOrganizationID as [SectionID],
		E.CustodyStorageAreaID as [StorageAreaID],
		E.CustodyStorageLocationCode as [StorageLocationCode],
		E.CustodyLockboxID as [LockboxID],
		E.ExternalId,
		E.EvidenceIDSortKey,
		ES2.EvidenceSubmissionID,
		ES2.ParentId,
		ES2.Verified,
		ES2.SubmitCarrierPackageId
	FROM Evidence E
	INNER JOIN EvidenceStatus ES ON E.EvidenceStatusCode = ES.EvidenceStatusCode
	INNER JOIN @RC RC ON E.FSLabNum = RC.CaseNum 
	INNER JOIN EvidenceSubmission ES2 ON E.FSLabNum = ES2.FSLabNum AND E.EvidenceType = ES2.EvidenceType AND E.EvidenceID = ES2.EvidenceID -- AND E.CurrentSubmissionNum = ES2.SubmissionNum
	WHERE ES2.ParentId IS NULL
UNION ALL
	SELECT
			CONVERT(VARCHAR(255), MySort + '-' + CONVERT(VARCHAR(255), RIGHT(CONVERT(VARCHAR, (ROW_NUMBER() OVER (ORDER BY E.EvidenceIDSortKey)+1000)),3))),
			SortLevel + 1,
			E.FSLabNum as [CaseNum],
			ES2.SubmissionNum,
			E.CurrentSubmissionNum,
			E.EvidenceType,
			E.EvidenceID as [EvidenceNum],
			E.Description,
			E.Comments,
			ES.EvidenceStatusCode as [StatusCode],
			ES.EvidenceStatusDescription as [Status],
			E.CustodyEmployeeID as [EmployeeID],
			E.CustodyLocationID as [LabID],
			E.CustodyOrganizationID as [SectionID],
			E.CustodyStorageAreaID as [StorageAreaID],
			E.CustodyStorageLocationCode as [StorageLocationCode],
			E.CustodyLockboxID as [LockboxID],
			E.ExternalId,
			E.EvidenceIDSortKey,
			ES2.EvidenceSubmissionID,
			ES2.ParentId,
			ES2.Verified,
			ES2.SubmitCarrierPackageId
		FROM Evidence E
		INNER JOIN EvidenceStatus ES ON E.EvidenceStatusCode = ES.EvidenceStatusCode
		INNER JOIN @RC RC ON E.FSLabNum = RC.CaseNum 
		INNER JOIN EvidenceSubmission ES2 ON E.FSLabNum = ES2.FSLabNum AND E.EvidenceType = ES2.EvidenceType AND E.EvidenceID = ES2.EvidenceID --AND E.CurrentSubmissionNum = ES2.SubmissionNum
		INNER JOIN MyEvidence ME ON ME.EvidenceSubmissionID = ES2.ParentId
)  INSERT INTO @MyEvidence(MySort, SortLevel, CaseNum, SubmissionNum, CurrentSubmissionNum, EvidenceType, EvidenceNum, [Description], Comments, StatusCode, [Status], EmployeeID, LabID, SectionID, StorageAreaID, StorageLocationCode, LockboxID, ExternalId, EvidenceIDSortKey, EvidenceSubmissionID, ParentId, Verified, SubmitCarrierPackageId)
(SELECT MySort, SortLevel, CaseNum, SubmissionNum, CurrentSubmissionNum, EvidenceType, EvidenceNum, [Description], Comments, StatusCode, [Status], EmployeeID, LabID, SectionID, StorageAreaID, StorageLocationCode, LockboxID, ExternalId, EvidenceIDSortKey, EvidenceSubmissionID, ParentId, Verified, SubmitCarrierPackageId FROM MyEvidence)
-- variable used to determine if evidence sorting is based on Evidence Sort ID Key only or using advanced calculation written by Roger:
DECLARE @useEvidenceIdSortKeyOnly BIT
SELECT @useEvidenceIdSortKeyOnly = CASE WHEN UPPER(SettingValue) IN ('Y', 'T', '1', 'TRUE', 'ON', 'YES') THEN 1 ELSE 0 END FROM FASettings WHERE SettingName = 'EvidenceSortKeyOrderInLabReportDatasetEvidence'
SET @useEvidenceIdSortKeyOnly = ISNULL(@useEvidenceIdSortKeyOnly, 0)
-- Evidence Listing:
IF @useEvidenceIdSortKeyOnly = 1
BEGIN

SELECT
@CaseNum AS [CaseNum], RC.CaseNum AS [OriginCaseNum], RC.seq AS [MyCaseSequence], mEv.EvidenceIDSortKey, mEv.MySort, mEv.SortLevel, CRE.AgencyEvidenceID, 
Case When (CRE.AgencyEvidenceID != '') AND (CRE.AgencyEvidenceID IS NOT NULL) THEN ' ('+CRE.AgencyEvidenceID+')'
ELSE '' END AS [FormattedAgencyEvidenceId],
CRE.SubmissionNum, mEv.EvidenceType, 
RDsTD.[Description] AS [EvidenceTypeDescription], mEv.EvidenceNum, 
Case 
When (CRE.CaseNum = CRE.RelatedCaseNum) THEN RDsTD.[Description] + ' ' + mEv.EvidenceNum
ELSE 
(CRE.RelatedCaseNum + ' -'+ CHAR(13) + RDsTD.[Description] + ' ' + mEv.EvidenceNum)
END AS [FormattedEvidenceId],
Case 
When ((CRE.CustomDescription IS NOT NULL) OR (CRE.CustomDescription != '')) THEN CRE.CustomDescription
ELSE mEv.[Description]
END AS [DominantEvidenceDescription],
mEv.[Description],
CRE.CustomDescription
FROM @RC AS RC
INNER JOIN @MyEvidence AS mEv ON RC.CaseNum = mEv.CaseNum
INNER JOIN @myCREvidenceExamTable AS CRE ON mEv.CaseNum = CRE.SubmissionCaseNum AND mEv.SubmissionNum = CRE.SubmissionNum AND mEv.EvidenceType = CRE.EvidenceType AND mEv.EvidenceNum = CRE.EvidenceNum 
INNER JOIN [dbo].[RDSTableData] AS RDsTD ON mEv.EvidenceType = RDsTD.Code AND RDsTD.RDSTableId = (SELECT RDSTableId FROM RDSTable WHERE [Description] like ('EvidenceType'))
ORDER BY RC.seq, mEv.EvidenceIDSortKey

END

ELSE
BEGIN

SELECT
@CaseNum AS [CaseNum], RC.CaseNum AS [OriginCaseNum], RC.seq AS [MyCaseSequence], mEv.EvidenceIDSortKey, mEv.MySort, mEv.SortLevel, CRE.AgencyEvidenceID, 
Case When (CRE.AgencyEvidenceID != '') AND (CRE.AgencyEvidenceID IS NOT NULL) THEN ' ('+CRE.AgencyEvidenceID+')'
ELSE '' END AS [FormattedAgencyEvidenceId],
CRE.SubmissionNum, mEv.EvidenceType, 
RDsTD.[Description] AS [EvidenceTypeDescription], mEv.EvidenceNum, 
Case 
When (CRE.CaseNum = CRE.RelatedCaseNum) THEN RDsTD.[Description] + ' ' + mEv.EvidenceNum
ELSE 
(CRE.RelatedCaseNum + ' -' + CHAR(13) + RDsTD.[Description] + ' ' + mEv.EvidenceNum)
END AS [FormattedEvidenceId],
Case 
When ((CRE.CustomDescription IS NOT NULL) OR (CRE.CustomDescription != '')) THEN CRE.CustomDescription
ELSE mEv.[Description]
END AS [DominantEvidenceDescription],
mEv.[Description],
CRE.CustomDescription
FROM @RC AS RC
INNER JOIN @MyEvidence AS mEv ON RC.CaseNum = mEv.CaseNum
INNER JOIN @myCREvidenceExamTable AS CRE ON mEv.CaseNum = CRE.SubmissionCaseNum AND mEv.SubmissionNum = CRE.SubmissionNum AND mEv.EvidenceType = CRE.EvidenceType AND mEv.EvidenceNum = CRE.EvidenceNum 
INNER JOIN [dbo].[RDSTableData] AS RDsTD ON mEv.EvidenceType = RDsTD.Code AND RDsTD.RDSTableId = (SELECT RDSTableId FROM RDSTable WHERE [Description] like ('EvidenceType'))
ORDER BY RC.seq, mEv.MySort, mEv.SortLevel

END


-- Result Statement
SELECT mLRR.CaseNum, mLRR.RecordNum, RS.Id, RS.CategoryName, RS.Body, RS.BodyRtf, RS.Sort 
from @myLabReportRequestTable AS mLRR 
INNER JOIN  [dbo].[ResultDataset] AS R ON mLRR.CaseNum = R.FSLabNum AND mLRR.RecordNum = R.CaseID
INNER JOIN [wsCommon].[ResultStatement] AS RS ON R.ResultDatasetID = RS.AnalysisId
WHERE RS.Body IS NOT NULL AND LTRIM(RTRIM(RS.Body)) != ''
ORDER BY R.ResultDatasetID, RS.Sort


-- Result Table Header
SELECT TOP 1 mLRR.CaseNum, mLRR.RecordNum,
(SELECT TOP 1 RTCD1.ColumnCaption FROM [wscommon].[ResultTableColumnDefinition] AS RTCD1
INNER JOIN [wsCommon].[ResultTable] AS RT1 ON RTCD1.ResultTableId = RT1.Id
INNER JOIN [dbo].[ResultDataset] AS R1 ON RT1.AnalysisId = R1.ResultDatasetID
INNER JOIN @myLabReportRequestTable AS mLRR1 ON R1.FSLabNum = mLRR1.CaseNum AND R1.CaseID = mLRR1.RecordNum
WHERE RTCD1.ResultTableColumnType = 0 GROUP BY RTCD1.ColumnCaption
) AS ColumnType0Name,
(SELECT TOP 1 RTCD1.ColumnCaption FROM [wscommon].[ResultTableColumnDefinition] AS RTCD1
INNER JOIN [wsCommon].[ResultTable] AS RT1 ON RTCD1.ResultTableId = RT1.Id
INNER JOIN [dbo].[ResultDataset] AS R1 ON RT1.AnalysisId = R1.ResultDatasetID
INNER JOIN @myLabReportRequestTable AS mLRR1 ON R1.FSLabNum = mLRR1.CaseNum AND R1.CaseID = mLRR1.RecordNum
WHERE RTCD1.ResultTableColumnType = 1 GROUP BY RTCD1.ColumnCaption
) AS ColumnType1Name
FROM @myLabReportRequestTable AS mLRR 
INNER JOIN  [dbo].[ResultDataset] AS R ON mLRR.CaseNum = R.FSLabNum AND mLRR.RecordNum = R.CaseID
INNER JOIN [wsCommon].[ResultTable] AS RT ON R.ResultDatasetID = RT.AnalysisId AND RT.CategoryName = 'RESULTS'
INNER JOIN [wsCommon].[ResultTableData] AS RTD ON RT.Id = RTD.ResultTableId
GROUP BY mLRR.CaseNum, mLRR.RecordNum


-- Result Table
SELECT mLRR.CaseNum, mLRR.RecordNum, RTD.Items, RTD.Result
FROM @myLabReportRequestTable AS mLRR 
INNER JOIN  [dbo].[ResultDataset] AS R ON mLRR.CaseNum = R.FSLabNum AND mLRR.RecordNum = R.CaseID
INNER JOIN [wsCommon].[ResultTable] AS RT ON R.ResultDatasetID = RT.AnalysisId AND RT.CategoryName = 'RESULTS'
INNER JOIN [wsCommon].[ResultTableData] AS RTD ON RT.Id = RTD.ResultTableId
ORDER BY R.ResultDatasetID, RTD.Sort


-- Note Table Data
SELECT TOP 1 mLRR.CaseNum, mLRR.RecordNum,
(SELECT TOP 1 RTCD1.ColumnCaption FROM [wscommon].[ResultTableColumnDefinition] AS RTCD1
INNER JOIN [wsCommon].[ResultTable] AS RT1 ON RTCD1.ResultTableId = RT1.Id
INNER JOIN [dbo].[ResultDataset] AS R1 ON RT1.AnalysisId = R1.ResultDatasetID
INNER JOIN @myLabReportRequestTable AS mLRR1 ON R1.FSLabNum = mLRR1.CaseNum AND R1.CaseID = mLRR1.RecordNum
WHERE RTCD1.ResultTableColumnType = 3 GROUP BY RTCD1.ColumnCaption
) AS ColumnType3Name,
(SELECT TOP 1 RTCD1.ColumnCaption FROM [wscommon].[ResultTableColumnDefinition] AS RTCD1
INNER JOIN [wsCommon].[ResultTable] AS RT1 ON RTCD1.ResultTableId = RT1.Id
INNER JOIN [dbo].[ResultDataset] AS R1 ON RT1.AnalysisId = R1.ResultDatasetID
INNER JOIN @myLabReportRequestTable AS mLRR1 ON R1.FSLabNum = mLRR1.CaseNum AND R1.CaseID = mLRR1.RecordNum
WHERE RTCD1.ResultTableColumnType = 4 GROUP BY RTCD1.ColumnCaption
) AS ColumnType4Name,
(SELECT TOP 1 RTCD1.ColumnCaption FROM [wscommon].[ResultTableColumnDefinition] AS RTCD1
INNER JOIN [wsCommon].[ResultTable] AS RT1 ON RTCD1.ResultTableId = RT1.Id
INNER JOIN [dbo].[ResultDataset] AS R1 ON RT1.AnalysisId = R1.ResultDatasetID
INNER JOIN @myLabReportRequestTable AS mLRR1 ON R1.FSLabNum = mLRR1.CaseNum AND R1.CaseID = mLRR1.RecordNum
WHERE RTCD1.ResultTableColumnType = 5 GROUP BY RTCD1.ColumnCaption
) AS ColumnType5Name
FROM @myLabReportRequestTable AS mLRR 
INNER JOIN  [dbo].[ResultDataset] AS R ON mLRR.CaseNum = R.FSLabNum AND mLRR.RecordNum = R.CaseID
INNER JOIN [wsCommon].[ResultTable] AS RT ON R.ResultDatasetID = RT.AnalysisId AND RT.CategoryName = 'NOTES'
INNER JOIN [wsCommon].[ResultTableData] AS RTD ON RT.Id = RTD.ResultTableId
GROUP BY mLRR.CaseNum, mLRR.RecordNum


-- Note Table Data
SELECT mLRR.CaseNum, mLRR.RecordNum, RTD.Value, RTD.[Type], RTD.Notes
FROM @myLabReportRequestTable AS mLRR 
INNER JOIN  [dbo].[ResultDataset] AS R ON mLRR.CaseNum = R.FSLabNum AND mLRR.RecordNum = R.CaseID
INNER JOIN [wsCommon].[ResultTable] AS RT ON R.ResultDatasetID = RT.AnalysisId AND RT.CategoryName = 'NOTES'
INNER JOIN [wsCommon].[ResultTableData] AS RTD ON RT.Id = RTD.ResultTableId
ORDER BY R.ResultDatasetID, RTD.Sort


-- Additional Report Text
SELECT mLRR.CaseNum, mLRR.RecordNum, '     *   ' AS [PrefixFormat], LRAT.ReportReturnTextCode, RRT.ReportReturnText, RRT.Sort FROM @myLabReportRequestTable AS mLRR 
INNER JOIN [dbo].[LabReportRequestAdditionalReportText] AS LRAT ON mLRR.Id = LRAT.LabReportRequestId
INNER JOIN [dbo].[ReportReturnText] AS RRT ON  LRAT.ReportReturnTextCode = RRT.ReportReturnTextCode
ORDER BY RRT.ReportReturnText


-- Examiner Assigned
SELECT mLRR.CaseNum, mLRR.RecordNum, 
[dbo].[GetFormattedReportName] (E.Title, E.FirstName, E.MiddleName, E.LastName, E.Suffix) AS [ReportName],
ISNULL(STUFF(STUFF(STUFF(E.PhoneNumber, 7, 0, '-'), 4, 0, ') '), 1, 0, '('), '') AS ExaminerPhone
FROM @myLabReportRequestTable AS mLRR 
INNER JOIN [dbo].[Case] AS C ON mLRR.CaseNum = C.FSLabNum AND mLRR.RecordNum = C.CaseID
INNER JOIN [dbo].[Employee] AS E ON C.ExaminerID = E.EmployeeID


-- End Placeholder
SELECT TOP 1 CaseNum, RecordNum FROM @myLabReportRequestTable
