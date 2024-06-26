/********************************************************
	Create database and tables

**********************************************************/

IF DB_ID('Company') IS NULL CREATE DATABASE Company;
GO

USE Company;
GO


IF OBJECT_ID('Departments', 'U') IS NULL CREATE TABLE Departments 
(
	department_id int IDENTITY(1,1),
	department_name varchar(50) NOT NULL UNIQUE,
	PRIMARY KEY(department_id),
);
GO


IF OBJECT_ID('Employees', 'U') IS NULL CREATE TABLE Employees
(
	employee_id int IDENTITY(1,1),
	fname varchar(50) NOT NULL,
	lname varchar(50) NOT NULL,
	name AS fname + ' ' + lname,
	address varchar(100),
	employment_date DATE NOT NULL,
	phone_no varchar(8),
	PRIMARY KEY(employee_id),
);
GO


IF OBJECT_ID('DepartmentEmployees', 'U') IS NULL CREATE TABLE DepartmentEmployees 
(
	department_id int,
	employee_id int,
	PRIMARY KEY(department_id, employee_id),

	FOREIGN KEY(employee_id) 
	REFERENCES Employees(employee_id),

	FOREIGN KEY(department_id) 
	REFERENCES Departments(department_id),
);
GO


IF OBJECT_ID('Managers', 'U') IS NULL CREATE TABLE Managers
(
	department_id int NOT NULL,
	employee_id int NOT NULL,
	PRIMARY KEY(department_id, employee_id),

	FOREIGN KEY(employee_id) 
	REFERENCES Employees(employee_id),

	FOREIGN KEY(department_id) 
	REFERENCES Departments(department_id),
);
GO


IF OBJECT_ID('AbsenceTypes', 'U') IS NULL CREATE TABLE AbsenceTypes
(
	absence_type_id int IDENTITY(1,1),
	absence_type varchar(50) NOT NULL UNIQUE,
	planned bit NOT NULL,
	PRIMARY KEY(absence_type_id),

);
GO


IF OBJECT_ID('AbsencePeriods', 'U') IS NULL CREATE TABLE AbsencePeriods 
(
	start_date DATE NOT NULL,
	end_date DATE,
	days_absent AS DATEDIFF(dd, start_date, DATEADD(dd, 1, end_date)),
	employee_id int NOT NULL,
	absence_type_id int NOT NULL,
	request_id int,
	PRIMARY KEY(start_date, employee_id),

	FOREIGN KEY(employee_id) 
	REFERENCES Employees(employee_id),

	FOREIGN KEY(absence_type_id) 
	REFERENCES AbsenceTypes(absence_type_id),
);
GO


IF OBJECT_ID('PTORequests', 'U') IS NULL CREATE TABLE PTORequests 
(
	request_id int IDENTITY(1,1),
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	employee_id int NOT NULL,
	absence_type_id int NOT NULL,
	approval_status bit NOT NULL DEFAULT 0,
	PRIMARY KEY(request_id),

	FOREIGN KEY(employee_id) 
	REFERENCES Employees(employee_id),

	FOREIGN KEY(absence_type_id) 
	REFERENCES AbsenceTypes(absence_type_id),
);
GO


/* Adding foreing keys for tables*/
ALTER TABLE AbsencePeriods
ADD CONSTRAINT FK4_AbsencePeriods
FOREIGN KEY(request_id) 
REFERENCES PTORequests(request_id);
GO



/********************************************************
	Create procedures for adding data and getting reports

**********************************************************/

/* Register new employee */
CREATE PROCEDURE spNewEmployee
(@Firstname varchar(50),
@Lastname varchar(50),
@Address varchar(100),
@EmploymentDate DATE,
@PhoneNumber varchar(8))
AS
BEGIN
	INSERT INTO Employees (fname, lname, address, employment_date, phone_no)
	VALUES(@Firstname, @Lastname, @Address, @EmploymentDate, @PhoneNumber)
END
GO


/* Create new absence period in system */
CREATE PROCEDURE spRegisterNewAbsence
(@StartDate DATE, 
@EndDate DATE, 
@EmployeeID int, 
@AbsenceTypeID int)
AS
BEGIN
	INSERT INTO AbsencePeriods (start_date, end_date, employee_id, absence_type_id)
	VALUES (@StartDate, @EndDate, @EmployeeID, @AbsenceTypeID);
END
GO


/* Create new PTO request in system */
CREATE PROCEDURE spRegisterNewPTORequest
(@StartDate DATE, 
@EndDate DATE, 
@EmployeeID int, 
@AbsenceTypeID int)
AS
BEGIN
	INSERT INTO PTORequests(start_date, end_date, employee_id, absence_type_id)
	VALUES (@StartDate, @EndDate, @EmployeeID, @AbsenceTypeID);
END
GO


/* List of employees in department */
CREATE PROCEDURE spGetAllEmployees
(@DepartmentID int)
AS
BEGIN
	SELECT 
		emp.name AS 'Employee Name', 
		emp.address AS 'Home Address', 
		emp.employment_date AS 'Employment date',
		department_name AS 'Department',
		(SELECT name FROM Employees WHERE employee_id = man.employee_id AND de.department_id = man.department_id) AS 'Manager'
	FROM Employees emp 
	INNER JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id
	INNER JOIN Departments dep ON de.department_id = dep.department_id
	INNER JOIN Managers man ON man.department_id = dep.department_id
	WHERE dep.department_id = @DepartmentID; 
END
GO


/* Generate a list of all employees currently not absent */
CREATE PROCEDURE spGetAbsentEmployeesByDepartment
(@DepartmentID int)
AS
BEGIN
	SELECT 
		name AS 'Employee',
		department_name AS 'Department',
		(SELECT name FROM Employees WHERE employee_id = man.employee_id) AS 'Manager'
	FROM Employees emp
	INNER JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id 
	INNER JOIN Departments dep ON dep.department_id = de.department_id
	INNER JOIN Managers man ON man.department_id = dep.department_id
	WHERE emp.employee_id IN 
		(SELECT 
			DISTINCT(ab.employee_id)
		FROM AbsencePeriods ab 
		Left JOIN Employees emp 
		ON emp.employee_id = ab.employee_id 
		WHERE ab.end_date IS NULL)
	AND de.department_id = @DepartmentID;
END
GO


/* Generate list of absence periods for all employees of a specific employee*/
CREATE PROCEDURE spGetEmployeeAbsences
(@EmployeeID int)
AS
BEGIN
	SELECT 
		name AS 'Employee', 
		dep.department_name AS 'Department',
		start_date AS 'Date',
		days_absent AS 'Days absent', 
		(SELECT absence_type 
		FROM AbsenceTypes 
		WHERE absence_type_id = ab.absence_type_id) 
		AS 'Absence Reason' 
	FROM Employees emp
	INNER JOIN AbsencePeriods ab ON emp.employee_id = ab.employee_id
	INNER JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id
	INNER JOIN Departments dep ON de.department_id = dep.department_id
	WHERE emp.employee_id = @EmployeeID
	ORDER BY start_date;
END
GO


/* Generate list of all employees with number of absences*/
CREATE PROCEDURE spNumberAbsencesForAllEMployees
AS
BEGIN
	SELECT 
		DISTINCT(name) AS 'Employee', 
		department_name AS 'Department', 
		count(*) OVER(PARTITION BY emp.employee_id) AS 'Number of Absences' 
	FROM Employees emp
	INNER JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id
	INNER JOIN Departments dep ON de.department_id = dep.department_id
	INNER JOIN AbsencePeriods ab ON emp.employee_id = ab.employee_id;
END
GO


/* Generate list of employees with 3 or more unplanned absences within the last year for a specific department */
CREATE PROCEDURE spMoreThanTwoAbsencesForDepartment 
(@DepartmentID int)
AS
BEGIN
	SELECT 
		name AS 'Employee', 
		department_name AS 'Department',
		absences AS 'Number of unplanned absence periods', 
		total_days AS 'Total days unplanned absence' 
	FROM 
		(SELECT
			DISTINCT(employee_id),
			count(*) OVER(PARTITION BY employee_id) AS absences,
			SUM(days_absent) OVER(PARTITION BY employee_id) AS total_days
		FROM AbsencePeriods ap 
		INNER JOIN AbsenceTypes ad 
		ON ap.absence_type_id = ad.absence_type_id 
		WHERE end_date > DATEADD(year, -1, GETDATE())
		AND planned = 0) A
	LEFT JOIN Employees emp ON A.employee_id = emp.employee_id
	INNER JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id
	INNER JOIN Departments dep ON de.department_id = dep.department_id
	WHERE absences >= 3 
	AND dep.department_id = @DepartmentID;
END
GO


/* View all unapproved PTO requests */
CREATE PROCEDURE spGetUnapprovedPTORequests
AS
BEGIN	
	SELECT 
		name AS 'Requester',
		department_name AS 'Department',
		start_date AS 'From',
		end_date AS 'To',
		absence_type AS 'Reason',
		approval_status AS 'Approval Status',
		(SELECT name FROM Employees WHERE employee_id = man.employee_id) AS 'Approver'
	FROM PTORequests pto
	LEFT JOIN Employees emp ON pto.employee_id = emp.employee_id
	LEFT JOIN DepartmentEmployees de ON emp.employee_id = de.employee_id
	LEFT JOIN Departments dep ON de.department_id = dep.department_id
	INNER JOIN AbsenceTypes ab ON pto.absence_type_id = ab.absence_type_id
	LEFT JOIN Managers man ON man.department_id = dep.department_id
	WHERE approval_status = 0;
END
GO


/* Approve a PTO request by request ID */
CREATE PROCEDURE spApprovePTORequest
(@RequestID int)
AS
BEGIN
	UPDATE PTORequests 
	SET approval_status = 1
	WHERE request_id = @RequestID;
END
GO



/********************************************************
	Trigger methods

**********************************************************/

/* Triggers on update of PTO request to insert new absence period */
CREATE TRIGGER AfterUPDATETrigger
ON PTORequests
AFTER UPDATE
AS
	INSERT INTO AbsencePeriods
	SELECT TOP 1
		inserted.start_date,
		inserted.end_date,
		inserted.employee_id,
		inserted.absence_type_id,
		inserted.request_id
	FROM inserted
GO
	


/********************************************************
	Adding data to table

**********************************************************/

/* Add departments to table*/
INSERT INTO Departments (department_name)
VALUES ('Finance');

INSERT INTO Departments (department_name)
VALUES ('Accounting');
GO

INSERT INTO Departments (department_name)
VALUES ('Management');
GO

/* Add employees to table*/
spNewEmployee 'Jeppe', 'Nielsen', 'Ovrevej 75, 4000 Roskilde', '2019-03-01', '31369952';
GO
spNewEmployee 'Lars', 'Larsen', 'Ringvejen 5, 2730 Herlev', '1995-04-01', '21365577';
GO
spNewEmployee 'Peter', 'Petersen', 'Vimmelskaftet 101, 4000 Roskilde', '2015-10-01', '42697813';
GO
spNewEmployee 'Lene', 'Jensen', 'Nedrevej 23, 4000 Roskilde', '2002-01-01', '75253695';
GO
spNewEmployee 'Carl', 'Carlsen', 'Vejnavn 10, 4066 By', '2024-01-01', '45368546';


/* Add employees to department roster */
INSERT INTO DepartmentEmployees (department_id, employee_id)
VALUES(1,2);

INSERT INTO DepartmentEmployees (department_id, employee_id)
VALUES(1,5);

INSERT INTO DepartmentEmployees (department_id, employee_id)
VALUES(2,3);

INSERT INTO DepartmentEmployees (department_id, employee_id)
VALUES(3,1);

INSERT INTO DepartmentEmployees (department_id, employee_id)
VALUES(3,4);


/* Add Managers */
INSERT INTO Managers (department_id, employee_id)
VALUES (1,1);

INSERT INTO Managers (department_id, employee_id)
VALUES (2,4);


/* Add possible types of absences to table*/
INSERT INTO AbsenceTypes (absence_type, planned) VALUES ('PTO', 1);
INSERT INTO AbsenceTypes (absence_type, planned) VALUES ('Scheduled annual leave', 1);
INSERT INTO AbsenceTypes (absence_type, planned) VALUES ('Illness', 0);
INSERT INTO AbsenceTypes (absence_type, planned) VALUES ('Unpaid leave', 1);
INSERT INTO AbsenceTypes (absence_type, planned) VALUES ('Unplanned time off', 0);
GO

/* Add absence periods to table*/
spRegisterNewAbsence '2024-01-07', '2024-01-08', 3, 1;
GO
spRegisterNewAbsence '2022-01-12', '2022-01-15', 1, 3;
GO
spRegisterNewAbsence '2024-05-01', '2024-05-21', 3, 1;
GO
spRegisterNewAbsence '2023-10-01', '2023-10-03', 3, 3;
GO
spRegisterNewAbsence '2023-07-27', '2023-07-28', 3, 3;
GO
spRegisterNewAbsence '2024-02-01', '2024-02-03', 3, 3;
GO
spRegisterNewAbsence '2023-03-01', '2023-03-03', 3, 3;
GO
spRegisterNewAbsence '2024-05-15', '2024-05-25', 4, 1;
GO
spRegisterNewAbsence '2024-06-10', NULL, 5, 3;
GO

/* Add a PTO request */
spRegisterNewPTORequest '2024-05-11', '2024-06-01', 2, 1;
GO
spRegisterNewPTORequest '2024-08-01', '2024-08-21', 4, 2;
GO


/********************************************************
	Using procedures to get data

**********************************************************/

/* List of all employees in department 1*/
spGetAllEmployees 1
GO

/* Employees present in department 1 */
spGetAbsentEmployeesByDepartment 1
GO

/* All absence periods for employee 3 */
spGetEmployeeAbsences 3
GO

/* Number of absence periods for all employees */
spNumberAbsencesForAllEMployees
GO

/* Employees with more than 2 absence periods within the past year in department 1*/
spMoreThanTwoAbsencesForDepartment 2
GO

/* Approve PTO request */
spApprovePTORequest 1
GO

/* View all unapproved PTO requests */
spGetUnapprovedPTORequests
GO




/********************************************************
	Get all data in database

**********************************************************/
/*View of all tables */
SELECT * FROM Employees;
SELECT * FROM Managers;
SELECT * FROM Departments;
SELECT * FROM DepartmentEmployees;
SELECT * FROM AbsencePeriods;
SELECT * FROM AbsenceTypes;
GO