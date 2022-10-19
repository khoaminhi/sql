use EmployeeMng_NoIndex
go
--Cap nhat luong cho mot nhan vien
create proc sp_UpdateSalary @id int = NULL, @changedate datetime = NULL, @rate money = NULL, @payfrequency tinyint = NULL
as
begin
	insert EmployeePayHistory
	values(@id, @changedate, @rate, @payfrequency, getdate())
end
go

--Tìm kiếm nhân viên theo phòng ban, theo ca làm việc, giới tính (tìm đa điều kiện)
create proc sp_SearchEmployee @departname nvarchar(50) = NULL, @shift nvarchar(50) = NULL, @gender nchar(1) =NULL
as
begin
	declare @strQuery nvarchar(3000)
	declare @paraList nvarchar(500)
	set @paraList = '
		@departname nvarchar(50),
		@shift nvarchar(50),
		@gender nchar(1)'
	--Ket cac bang lai truoc va loc sau
	set @strQuery = N'select distinct e.BusinessEntityID, d.Name as ''DepatmentName'', s.Name as N''Shifts'', e.Gender, e.NationalIDNumber, e.LoginID, e.JobTitle, e.BirthDate, e.MaritalStatus, e.HireDate, e.SalariedFlag, e.VacationHours, e.SickLeaveHours, e.CurrentFlag, e.rowguid, e.ModifiedDate
						from Employee e join EmployeeDepartmentHistory ed on e.BusinessEntityID = ed.BusinessEntityID
						join Shift s on s.ShiftID=ed.ShiftID
						join Department d on d.DepartmentID = ed.DepartmentID
						where (1=1)'
	if(@departname != N'')
		set @strQuery = @strQuery + ' and d.Name = @departname'
	if(@shift != N'')
		set @strQuery = @strQuery + ' and s.Name = @shift'
	if(@gender != N'')
		set @strQuery = @strQuery + ' and e.Gender = @gender'

	exec sp_executesql @strQuery, @paraList, @departname, @shift, @gender
end
go
----------

--Không cho phép xoá nhân viên, khi nhân viên nghỉ việc chỉ cập nhật lại EndDate.
create trigger trg_deleteEmployee
on Employee
for delete
as
begin
	raiserror(N'Not allowed to delete Employee', 16, 2)
	rollback tran
end
go
--Cap nhat lai Enddate
create trigger trg_EmploeeWorkStatus
on Employee
for update
as
if update(CurrentFlag)
begin
	if object_id('tempdb..#tableCurrentFlag') is not null
		drop table #tableCurrentFlag
	create table #tableCurrentFlag(ID int, CF bit)
	insert into	#tableCurrentFlag
	select e.BusinessEntityID, e.CurrentFlag
	from Employee e
	where e.CurrentFlag = 0

	declare cur cursor for
	select *
	from #tableCurrentFlag
	open cur
	declare @id int, @cf bit
	fetch next from cur into @id, @cf
	while @@FETCH_STATUS = 0
	begin
		if(@cf = 0)
		begin
			update EmployeeDepartmentHistory
			set EndDate = cast(getdate() as date), ModifiedDate = getdate()
			where BusinessEntityID = @id and EndDate is NULL
		end
		fetch next from cur into @id, @cf
	end
	close cur
	deallocate cur
end
go
---

---Nhân viên chỉ làm việc ở 1 phòng ban tại 1 thời điểm 
create trigger trg_EmployeeDepartment
on EmployeeDepartmentHistory
after insert
as
begin
	if exists(select *
				from inserted i
				where  exists (select ed.BusinessEntityID, ed.EndDate, min(ed.StartDate)
								from EmployeeDepartmentHistory ed
								where (i.BusinessEntityID = ed.BusinessEntityID) and (ed.EndDate is NULL) and i.StartDate > ed.StartDate
								group by ed.BusinessEntityID, ed.EndDate, ed.StartDate
								having max(ed.EndDate) is NULL
								)
	)
	begin
		raiserror (N'Please update an Employee''s EndDate is NULL!', 16, 2)
		rollback tran
	end
	
end
go

--Thống kê lương đã trả cho mỗi nhân viên theo từng năm

----######################
create function f_isLeapyear(@year int=null)
returns bit
as
begin
	if(@year % 400 = 0 or (@year % 4 = 0 and @year % 100 != 0))
		return 1
	return 0
end
go

--####### Tinh luong theo nam cua tung nhan vien ######################
create proc sp_EmployeeSalaryYear
as
begin
	declare @RateYear table(ID int, Year int, RateYear money)
	declare cur cursor scroll for 
		select ep.BusinessEntityID, ep.RateChangeDate, ep.Rate
		from EmployeePayHistory ep
		group by ep.BusinessEntityID, ep.RateChangeDate, ep.Rate
		order by ep.BusinessEntityID, ep.RateChangeDate
	
	open cur --mo con tro
	
	declare @id int, @ratechangedate datetime, @rate money --Bien luu gia tri cot ma cur giu
	declare @id2 int, @ratechangedate2 datetime, @rate2 money
	declare @totalYearSalary money = 0 --Luong cua mot nam
	declare @totalTemp money = 0 --Tinh luong cho nam sau (luong giao giua hai nam ma rate ben nam cu)
	declare @theLastDayofYear datetime --Chua ngay cuoi cung cua nam co rate
	declare @theFirstDayofYear datetime 
	declare @numbersyear smallint --xac dinh so nam lam viec de tinh toan
	declare @y int, @amountYearsGap smallint, @i smallint --@y la nam, @amountYearsGap la cach bao nhieu nam, @i la bien dem
	declare @amountday smallint
	declare @numberRows int = @@CURSOR_ROWS, @countRows int = 0
	
	fetch next from cur into @id, @ratechangedate, @rate
	--Vong lap
	while @@FETCH_STATUS=0 --Dieu kien thuc thi contro
	begin
		set @countRows += 1
		fetch next from cur into @id2, @ratechangedate2, @rate2
		fetch prior from cur into @id, @ratechangedate, @rate
		if (@id=@id2 and @countRows != @numberRows) --Neu dong tiep theo trung id---------------------------------------------------------------
			begin
				if (year(@ratechangedate)=year(@ratechangedate2)) --Trung nam luong co hieu luc--------------------------#############################
					begin
						set @amountday = datediff(dd, @ratechangedate, @ratechangedate2) --Tinh so ngay nhan luong, khong cong 1 vi de lan sau khac nam no se cong
						set @totalYearSalary += @amountday * @rate --Chua in ra man hinh bao gio qua nam khac moi in luong cua nam truoc
					end
				else --Khong trung nam ratechangedate---------------------------------------#######################################
					begin
						set @amountYearsGap = datediff(y, @ratechangedate, @ratechangedate2)
						if (@amountYearsGap = 1) --Hai nam lien tiep doi luong------------------------------------#################################
							begin	
								set @theLastDayofYear = dateadd(d, -1, dateadd(yy, datediff(yy, 0, @ratechangedate) + 1, 0))
								set @amountday = datediff(d, @ratechangedate, @theLastDayofYear) + 1
								set @totalYearSalary += @amountday * @rate
							--##########################
								insert @RateYear
								values(@id, year(@ratechangedate), @totalYearSalary)
								set @totalYearSalary = 0 --Set = 0 neu nam tiep theo la nhung lan thay doi rate trong 1 nam
								set @theFirstDayofYear = dateadd(yy, datediff(yy, 0, @ratechangedate2), 0) --Tinh nam dau cua ratechangedate2
								set @amountday = datediff(dd, @theFirstDayofYear, @ratechangedate2) + 1
								set @totalTemp = @amountday * @rate --########
							end
						else --khong phai 2 nam thay doi luong lien tiep-----------------------------------------###############################
							begin
								--in luong nam truoc ra
								set @theLastDayofYear = dateadd(d, -1, dateadd(yy, datediff(yy, 0, @ratechangedate) + 1, 0))
								set @amountday = datediff(d, @ratechangedate, @theLastDayofYear) + 1
								set @totalYearSalary += @amountday * @rate
								insert @RateYear
								values(@id, year(@ratechangedate), @totalYearSalary)
								set @totalYearSalary = 0
								--Dung vong lap in luong nhung nam co rate hien tai ma cur dang giu
								set @amountYearsGap = datediff(yy, @ratechangedate, @ratechangedate2)
								set @i = 1
								while (@i < @amountYearsGap)
									begin
										set @y = year(@ratechangedate) + @i
										if(dbo.f_isLeapyear(@y)=1)
											begin
												set @totalYearSalary = @rate * 366
												insert @RateYear
												values(@id, @y, @totalYearSalary)
												set @totalYearSalary = 0
											end
										else
											begin
												set @totalYearSalary = @rate * 365
												insert @RateYear
												values(@id, @y, @totalYearSalary)
												set @totalYearSalary = 0
											end
										set @i += 1
									end
								--Truong hop rate thay doi giua hai nam khac nhau can tinh so tien cua rate2
								set @theFirstDayofYear = dateadd(d, 0, dateadd(yy, datediff(yy, 0, @ratechangedate2), 0)) --Tinh nam dau cua ratechangedate2
								set @amountday = datediff(dd, @theFirstDayofYear, @ratechangedate2) --Khong cong them 1 vi luong tinh tu ngay ratechangedate va no se duoc cong vao vong lap toi
								set @totalTemp = @amountday * @rate --#########
							end
					end
			end
		else if(@id != @id2 or @countRows = @numberRows)--Khong trung id---------------------------------#########################################
			begin
				--Tinh so tien nam dau tien employee nhan
				set @theLastDayofYear = dateadd(dd, -1, dateadd(yy, datediff(yy, 0, @ratechangedate)+1, 0))
				set @amountday = datediff(dd, @ratechangedate, @theLastDayofYear) + 1
				set @totalYearSalary = @amountday * @rate + @totalTemp
				--#################
				insert @RateYear
				values(@id, year(@ratechangedate), @totalYearSalary)
				set @totalYearSalary = 0
				--Tinh nhung nam tiep theo cho toi bay gio
				set @amountYearsGap = datediff(yy, @ratechangedate, getdate())
				set @i = 1
				while (@i <= @amountYearsGap)
					begin
						set @y = year(@ratechangedate) + @i
						if(dbo.f_isLeapyear(@y)=1)
							begin
								set @totalYearSalary = @rate * 366
								insert @RateYear
								values(@id, @y, @totalYearSalary)
								set @totalYearSalary = 0
							end
						else
							begin
								set @totalYearSalary = @rate * 365
								insert @RateYear
								values(@id, @y, @totalYearSalary)
								set @totalYearSalary = 0
							end
					set @i += 1
					end
				set @totalYearSalary = 0
				set @totalTemp = 0 --Cho no ve 0 chu khong ##########
			end
		set @totalYearSalary += @totalTemp
		fetch next from cur into @id, @ratechangedate, @rate
	end
	close cur -- dong con tro
	deallocate cur --giai phong con tro
	select * from @RateYear
end
go



--######## Tinh tong luong theo tung phong ban ########################################################
create proc sp_EmployeeDepartmentSalary
as
begin	
	declare cur cursor scroll for 
		select e.BusinessEntityID, d.Name, ep.RateChangeDate, ep.Rate 
		from EmployeeDepartmentHistory ed join Department d on ed.DepartmentID = d.DepartmentID
			join Employee e on e.BusinessEntityID = ed.BusinessEntityID
			join EmployeePayHistory ep on ep.BusinessEntityID = e.BusinessEntityID
		where (ed.StartDate <= ep.RateChangeDate and ep.RateChangeDate <= ed.EndDate)
			or (ed.StartDate <= ep.RateChangeDate and ed.EndDate is NULL)
		group by d.DepartmentID, e.BusinessEntityID, ep.RateChangeDate, e.BusinessEntityID, d.Name, ep.Rate
	
	open cur --mo con tro

	declare @RateDepatment table(DepartmentName nvarchar(50), Salary money)
	declare @totalDeapartSalary money = 0
	declare @id int, @departname nvarchar(50), @ratechangedate datetime, @rate money --Bien luu gia tri cot ma cur giu
	declare @id2 int, @departname2 nvarchar(50), @ratechangedate2 datetime, @rate2 money
	declare @amountday smallint
	declare @numberRows int = @@CURSOR_ROWS, @countRows int = 0
	declare @ratechangedateNext datetime, @currentdatetime datetime
	
	fetch next from cur into @id, @departname, @ratechangedate, @rate
	--Vong lap
	while @@FETCH_STATUS=0 --Dieu kien thuc thi contro
	begin
		set @countRows += 1
		fetch next from cur into @id2, @departname2, @ratechangedate2, @rate2
		fetch prior from cur into @id, @departname, @ratechangedate, @rate
		--Kiem tra so dong da dem vi no se khon xu ly duoc dong cuoi cung @countRows voi @numberRows
		if (@id=@id2 and @countRows != @numberRows) --Neu dong tiep theo trung id---------------------------------------------------------------
			begin
				--Tinh thoi gian cho toi lan thay doi luong gan nhat khi chuyen sang phong ban khac (khong co truong hop cho toi bay gio o truong hop nay vi bao gio khac id moi xay ra va vi ratechangedate sap theo thu tu
				--Chua chac dong tiep theo la thoi gian chi cap nhat luong chu khong phai da chuyen tu phong ban khac ve lai nen van search
				select @ratechangedateNext = min(ep.RateChangeDate)
				from EmployeePayHistory ep
				where ep.BusinessEntityID = @id and ep.RateChangeDate > @ratechangedate
				
				set @amountday = datediff(dd, @ratechangedate, @ratechangedateNext)
				set @totalDeapartSalary += @amountday * @rate
			end
		else if(@id != @id2 or @countRows = @numberRows)--Khong trung id--#########################################
			begin
				--Tinh thoi gian cho toi lan thay doi luong gan nhat khi chuyen sang phong ban khac hoac cho toi bay gio
				select @ratechangedateNext = min(ep.RateChangeDate)
				from EmployeePayHistory ep
				where ep.BusinessEntityID = @id and ep.RateChangeDate > @ratechangedate
				if(@ratechangedateNext is NULL)
					set @ratechangedateNext = getdate()

				set @amountday = datediff(dd, @ratechangedate, @ratechangedateNext)
				set @totalDeapartSalary += @amountday * @rate
			end

		if(@departname != @departname2 or @countRows = @numberRows)
		begin
			insert @RateDepatment
			values(@departname, @totalDeapartSalary)
			set @totalDeapartSalary = 0
		end

		fetch next from cur into @id, @departname, @ratechangedate, @rate
	end
	close cur -- dong con tro
	deallocate cur --giai phong con tro

	select * from @RateDepatment
end
go