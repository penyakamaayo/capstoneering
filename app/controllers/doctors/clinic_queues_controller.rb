class Doctors::ClinicQueuesController < DoctorsController
	before_action :authenticate_user!
  # before_action :set_patient
  before_action :set_clinic
  before_action :set_clinic_queue
  before_action :set_in_progress, only: [:index, :start_queue]
	autocomplete :patient, :email

	def index
		# @clinics = Clinic.all

		@patient  = Patient.new
		@patients = Patient.all
		# @in_progress = ClinicQueue.queue_today.where(status: 2).last
	end

	def queue_autocomplete_patient
    term = params[:term]
    terms = make_terms_from term

    patients = Patient.where(terms).all
    render :json => patients.map { |d| {:id => d.id, :label => d.fullname_and_email, :value => d.fullname_and_email} }
  end

	def make_terms_from term
    terms = term.split.map{|t| "lastname ilike '%%%s%%'" % t}.join(" or ")    
  end

	def next_patient
		return if @clinic_queues.nil?
		return if @clinic_queues.empty?

		# If current_time >= schedule sa ClinicQueue.where(scheduled)
		# else
		# Go to ClinicQueue.where(not scheduled)

		# Status 1 -> In Queue, Status 2 -> In Progress, Status 3 -> finished
		# Queue Type 1 -> Walkin, Queue Type 2 -> Scheduled
		if @in_progress
			user_to_mail = @in_progress.patient

			# UserMailer.with(user: user_to_mail).finished_queue.deliver_now
			@in_progress.update(status: 3)
		end

		next_for_schedule = @clinic_queues.where(queue_type: 2).first

		# Check for current time
		# If there are any Appointments nga nalabyan na wala na serve,
		# Serve them next
		# else serve walk-in patients
		if next_for_schedule && DateTime.now >= next_for_schedule.schedule
			# UserMailer.with(user: user_to_mail).finished_queue.deliver_now
			next_for_schedule.update(status: 2)
			@in_progress = next_for_schedule
		else
			if next_for_queue = @clinic_queues.where(queue_type: 1).first
				next_for_queue.update(status: 2)

				user_to_mail = next_for_queue.patient

				# UserMailer.with(user: user_to_mail).turn_is_up.deliver_now
				@in_progress = next_for_queue
			else
				if next_for_schedule
					# UserMailer.with(user: user_to_mail).turn_is_up.deliver_now
					next_for_schedule.update(status: 2)
					@in_progress = next_for_schedule
				end
			end
		end

		redirect_to doctor_clinic_queues_url

		# clinic_queue_to_be_finished = @clinic_queues.first
		# clinic_queue_to_be_finished.update(status: 3) # First in queue is finished

		# redirect_to doctor_clinic_queues_url

		# clinic_queue_to_be_in_progress = @clinic_queues.first
		# clinic_queue_to_be_in_progress.update(status: 2) # Second in queue is In Progress
	end

	def start_queue
		qs = Appointment.doctor_appointments_today.to_a.map{|a| {user_id: a.user_id, clinic_id: a.clinic_id, schedule: a.schedule, queue_type: 2, status: 1} }

		ClinicQueue.create! qs

		# clinic_queues = @clinic_queues.pluck(:id)
		# in_progress = 1

		# set_worker_schedule(clinic_queues, in_progress)

		redirect_to doctor_clinic_queues_url, notice: "Started queue."
	end

	# def set_worker_schedule clinic_queues, in_progress
  #   Sidekiq.set_schedule(
  #     "auto_queue",
  #     {
  #       'cron' => "* * * * *", 'class' => "AutomateQueue",
  #       'args' => [{ clinic_queues: clinic_queues, in_progress: in_progress }]
  #     }
  #   )
  # end

	def cancel_todays_queue
		ClinicQueue.queue_today.destroy_all

		redirect_to doctor_clinic_queues_url, notice: "Queue was cancelled for today."
	end

	def create
		@patient = Patient.new(patient_params)
    if @patient.save
      @clinic_queue = ClinicQueue.create!(schedule: DateTime.now, user_id: @patient.id)

      redirect_to doctor_queue_path, notice: "Patient created successfully!"
    else
      redirect_to patient_book_appointment_url, notice: "Patient not created!! #{@patient.errors.first.full_message}"
    end
	end

	def add_existing_patient_to_queue
		user_field = params[:patient][:email]
    f_name, l_name, email = user_field.split(" ")

    user = User.find_by(email: email)

		@clinic_queue = user.clinic_queues.new(schedule: DateTime.now, clinic_id: @clinic.id, queue_type: 1, status: 1)

    if @clinic_queue.save
			# UserMailer.with(user: user).added_to_queue.deliver_now
      redirect_to doctor_clinic_queues_url, notice: "Patient added to queue successfully!"
    else
      redirect_to doctor_clinic_queues_url, alert: "There was a problem in adding patient to queue. #{@clinic_queue.errors.first.full_message}"
    end
	end

	def add_patient_to_queue
    @patient = Patient.new(
			firstname: params[:patient][:firstname],
			lastname: params[:patient][:lastname],
			email: params[:patient][:email],
			password: params[:patient][:password],
			password_confirmation: params[:patient][:password_confirmation]
		)

    if @patient.save
			user = User.find(@patient.id)

      @clinic_queue = ClinicQueue.create!(schedule: DateTime.now, user_id: user.id, clinic_id: @clinic.id, queue_type: 1, status: 1)
      redirect_to doctor_clinic_queues_url, notice: "Patient added to queue successfully!"
    else
      redirect_to doctor_clinic_queues_url, alert: "There was a problem in adding patient to queue. #{@clinic_queue.errors.first.full_message}"
    end
  end

	def destroy
		@clinic_queue = ClinicQueue.find(params[:id])
		@clinic_queue.destroy

		redirect_to doctor_clinic_queues_url, notice: "Successfully removed from queue!"
	end

	private
	def set_clinic
		clinic_id = ClinicSchedule.where(day: Date.today.strftime("%A")).first.clinic_id

		@clinic = Clinic.find(clinic_id)
	end

	def set_clinic_queue
		@clinic_queues = ClinicQueue.queue_today.where(status: 1).order('queue_type DESC, schedule')
	end

	def set_in_progress
		# return nil if @clinic_queues.empty?
		@in_progress = ClinicQueue.queue_today.where(status: 2).last
	end

	def set_patient
	end
end
