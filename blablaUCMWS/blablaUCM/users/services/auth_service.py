import hashlib
import logging
import re
import secrets
import string
from datetime import timedelta

from decouple import config
from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.db.models import F
from django.utils import timezone
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from rest_framework_simplejwt.tokens import RefreshToken

from services.email.email_service import Email
from users.models import USERNAME_REGEX, Users, UserType, normalize_email
from users.services.exceptions import (EmailAlreadyRegisteredError, EmailDeliveryError, EmailDomainNotAllowedError,
    GoogleEmailMissingError, IncorrectPasswordError, InvalidGoogleTokenError, InvalidTokenError, InvalidUsernameError,
    InvalidUserTypeError, TokenExpiredError, UnverifiedEmailError, UsernameAlreadyTakenError, UserNotFoundError)

# Logger para ir almacenando los logs
logger = logging.getLogger(__name__)

# Longitud del codigo de verificacion que se manda por correo.

TOKEN_LENGTH = 6

# Claim donde viaja la generacion de sesiones de la cuenta 
SESSION_EPOCH_CLAIM = 'sv'

# Propositos de los codigos de verificacion
PURPOSE_VERIFY_EMAIL = 'verify_email'
PURPOSE_RESET_PASSWORD = 'reset_password'
PURPOSE_CHANGE_EMAIL = 'change_email'
PURPOSE_LOGIN_2FA = 'login_2fa'
PURPOSE_CHANGE_2FA = 'change_2fa'

# Propositos que se consideran equivalentes entre si
INTERCHANGEABLE_PURPOSES = {PURPOSE_VERIFY_EMAIL, PURPOSE_RESET_PASSWORD}

# Texto que se devuelve cuando el correo no es de un dominio admitido
EMAIL_DOMAIN_ERROR_MESSAGE = "El correo no pertenece al dominio permitido, utiliza otro"

# Servicio con la logica de autenticacion, registro y verificacion por correo
class AuthService:

    # Genera un codigo alfanumerico aleatorio y devuelve el codigo y su hash
    @staticmethod
    def generate_token():
        token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(TOKEN_LENGTH))
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        return token, token_hash

    # Comprueba que el codigo aportado coincida con el hash almacenado
    @staticmethod
    def verify_token(user_input, stored_hash):
        input_hash = hashlib.sha256(user_input.encode()).hexdigest()
        return input_hash == stored_hash

    # Deduce para que se esta pidiendo el codigo
    @staticmethod
    def purpose_for_request(user, to_email=None):
        """
        El cliente no manda el proposito, se deduce:
        hay una direccion de destino distinta -> cambio de correo
        la cuenta no esta verificada todavia  -> verificacion de la cuenta
        en cualquier otro caso                -> restablecer la contraseña
        """
        if to_email:
            return PURPOSE_CHANGE_EMAIL
        if not user.is_verify:
            return PURPOSE_VERIFY_EMAIL
        return PURPOSE_RESET_PASSWORD

    # Genera un codigo, lo manda por correo y lo deja guardado en la cuenta
    @staticmethod
    def send_verification_code(user, to_email=None, purpose=None):
        """
        to_email solo llega con valor en el flujo de cambio de correo desde el perfil
        Solo se guarda el hash del codigo, nunca el codigo en claro
        """
        token, hashed_token = AuthService.generate_token()

        try:
            email_service = Email()
            email_service.send_verification_email(to=to_email or user.email, token=token)
        except Exception as e:
            logger.error(f"Error sending verification email: {str(e)}")
            raise EmailDeliveryError(user.id)

        user.token = hashed_token
        user.token_purpose = purpose or AuthService.purpose_for_request(user, to_email)
        user.token_expiration = timezone.now() + timedelta(
            minutes=config('TOKEN_EXPIRATION_TIME', cast=int, default=5)
        )
        user.save()

        logger.info(f"Token generated for user ID: {user.id} with purpose: {user.token_purpose}")
        return user

    # Comprueba que el codigo pendiente sirva para lo que se quiere hacer con el
    @staticmethod
    def assert_purpose(user, required):
        """
        Un codigo emitido para el segundo factor del login no vale para cambiar la contraseña, ni al reves
        """
        stored = user.token_purpose
        if stored is None:
            return

        if stored == required:
            return

        if {stored, required} <= INTERCHANGEABLE_PURPOSES:
            return

        logger.warning(
            f"Token purpose mismatch for user ID: {user.id}: "
            f"issued for {stored}, used for {required}"
        )
        raise InvalidTokenError(user.id)

    # Consume el codigo de verificacion y aplica los cambios que se pidan
    @staticmethod
    def consume_verification_code(user, token, email=None, password=None, validate=False,
                                  required_purpose=None):
        """
        Comprueba el codigo y, si es correcto, aplica los cambios solicitados
        """
        # Si nunca se pidio un codigo, o ya se consumio, no hay nada que verificar
        if not user.token or not user.token_expiration:
            logger.warning(f"Verification attempt without a pending token for user ID: {user.id}")
            raise InvalidTokenError(user.id)

        if user.token_expiration < timezone.now():
            logger.warning(f"Expired verification token for user ID: {user.id}")
            raise TokenExpiredError(user.id)

        if not AuthService.verify_token(token, user.token):
            logger.warning(f"Invalid verification token for user ID: {user.id}")
            raise InvalidTokenError(user.id)

        if required_purpose is None:
            if email:
                required_purpose = PURPOSE_CHANGE_EMAIL
            elif password:
                required_purpose = PURPOSE_RESET_PASSWORD
            elif validate:
                required_purpose = PURPOSE_VERIFY_EMAIL
        if required_purpose is not None:
            AuthService.assert_purpose(user, required_purpose)

        # La politica de contraseñas se comprueba antes, para no consumir el codigo
        if password:
            AuthService.assert_password_is_acceptable(password, user=user)

        if email:
            # El correo nuevo tiene que ser de un dominio admitido
            AuthService.assert_email_domain_is_allowed(email)
            if AuthService.email_is_taken(email, excluding=user):
                logger.warning(f"Rejected email change for user ID: {user.id}: address already in use")
                raise EmailAlreadyRegisteredError(email)
            user.email = email
        if password:
            user.set_password(password)
        if validate:
            user.is_verify = True

        # El codigo es de un solo uso
        user.token = None
        user.token_expiration = None
        user.token_purpose = None
        user.save()

        # Si se cambia la contraseña, se cierra la sesion en todos los dispositivos y se invalidan los refresh tokens emitidos
        if password:
            AuthService.revoke_all_sessions(user)

        logger.info(f"Post_verify_code successful. User data updated successfully for user ID: {user.id}")
        return user

    # Arranca el segundo factor y devuelve el metodo empleado
    @staticmethod
    def start_second_factor(user):
        """
        Se devuelve el metodo en lugar de no devolver nada precisamente para que sepa que metodo se ha usado
        """
        AuthService.send_verification_code(user, purpose=PURPOSE_LOGIN_2FA)
        # En un futuro se pueden añadir mas metodos, como TOTP
        return 'email'

    # Indica si la cuenta tiene un codigo pendiente de canjear
    @staticmethod
    def has_pending_code(user):
        return bool(user.token and user.token_expiration)

    # Comprueba el codigo del segundo factor y lo consume
    @staticmethod
    def check_second_factor(user, code):
        """
        Delega en consume_verification_code, que es el mismo mecanismo que usa la recuperacion de cuenta
        Exige que el codigo se emitiera para el login
        """
        AuthService.consume_verification_code(user, code, required_purpose=PURPOSE_LOGIN_2FA)

    # Indica si la cuenta puede acreditarse con una contraseña
    @staticmethod
    def can_use_password(user):
        """
        Las cuentas que solo entran por Google no tienen contraseña que pedir, dejan el campo a NULL en ese caso
        """
        return bool(user.password)

    # Arranca el cambio del ajuste y devuelve como hay que acreditarse
    @staticmethod
    def start_second_factor_change(user):
        """
        Quitar o poner el segundo factor exige volver a demostrar quien eres, se demuestra dependiendo de la cuenta,
        si tiene contraseña, con la contraseña, si solo entra por Google, con un codigo enviado a su correo
        """
        if AuthService.can_use_password(user):
            return 'password'

        AuthService.send_verification_code(user, purpose=PURPOSE_CHANGE_2FA)
        return 'email'

    # Activa o desactiva el segundo factor, acreditando antes la identidad
    @staticmethod
    def set_second_factor(user, enabled, password=None, code=None):
        """
        Se pide credencial tanto para activarlo como para desactivarlo
        Lanza IncorrectPasswordError, InvalidTokenError o TokenExpiredError.
        """
        if AuthService.can_use_password(user):
            if not password or not user.check_password(password):
                logger.warning(f"Rejected second factor change for user ID: {user.id}: wrong password")
                raise IncorrectPasswordError(user.id)
        else:
            # Sin esto, verify_token intentaria codificar un None
            if not code:
                logger.warning(f"Rejected second factor change for user ID: {user.id}: no code provided")
                raise InvalidTokenError(user.id)

            # Comprueba el codigo, exige que se emitiera para esto y lo consume
            AuthService.consume_verification_code(user, code, required_purpose=PURPOSE_CHANGE_2FA)

        user.has_2FA = enabled
        user.save()

        # Tocar el segundo factor revoca las sesiones abiertas
        AuthService.revoke_all_sessions(user)

        logger.info(f"Second factor set to {enabled} for user ID: {user.id}")
        return user

    # Indica si un correo ya esta en uso por una cuenta activa
    @staticmethod
    def email_is_taken(email, excluding=None):
        """
        excluding sirve para no chocar contra uno mismo al actualizar el perfil
        """
        qs = Users.objects.filter(email=normalize_email(email), is_deleted=False)
        if excluding is not None:
            qs = qs.exclude(pk=excluding.pk)
        return qs.exists()

    # Indica si un nombre de usuario ya esta en uso por una cuenta activa
    @staticmethod
    def username_is_taken(username, excluding=None):
        qs = Users.objects.filter(username=username, is_deleted=False)
        if excluding is not None:
            qs = qs.exclude(pk=excluding.pk)
        return qs.exists()

    # Invalida todos los tokens emitidos hasta ahora para esa cuenta
    @staticmethod
    def revoke_all_sessions(user):
        """
        Sube sessions_epoch, con lo que todo token que lleve un `sv` menor deja
        de valer. Cubre el access y el refresh de una vez, porque el claim se
        copia del refresh al access al emitirlo
        """
        # F() y no user.sessions_epoch + 1, dos revocaciones simultaneas leyendo el mismo valor dejarian el 
        # contador una generacion por detras, y con el los tokens de la primera seguirian valiendo
        user.sessions_epoch = F('sessions_epoch') + 1
        user.save(update_fields=['sessions_epoch'])
        # save() deja el atributo como una expresion F sin resolver, hay que recargarlo para que quien 
        # llame pueda emitir tokens con el valor nuevo
        user.refresh_from_db(fields=['sessions_epoch'])

        logger.info(f"All sessions revoked for user ID: {user.id} (epoch {user.sessions_epoch})")

    # Indica si un token esta revocado, comparando su generacion con la de la cuenta
    @staticmethod
    def token_is_revoked(user, token):
        """
        Un token sin el claim `sv` cuenta como generacion 0, que es donde empiezan todas las cuentas
        """
        return token.get(SESSION_EPOCH_CLAIM, 0) < user.sessions_epoch

    # Comprueba que una contraseña cumple AUTH_PASSWORD_VALIDATORS
    @staticmethod
    def assert_password_is_acceptable(raw_password, user=None):
        validate_password(raw_password, user=user)

    # Comprueba que el nombre de usuario cumpla el formato admitido
    @staticmethod
    def assert_username_is_acceptable(username):
        """
        Se impiden los nombres de usuario que no cumplan el formato
        """
        if not re.match(USERNAME_REGEX, username or ''):
            logger.warning("Rejected username with a not allowed format: %s", username)
            raise InvalidUsernameError(username)

    # Devuelve los dominios admitidos, o lista vacia si se admite cualquiera
    @staticmethod
    def allowed_email_domains():
        """
        ALLOWED_DOMAINS vale '*' por defecto, que permite cualquier dominio
        """
        return [d for d in settings.ALLOWED_DOMAINS if d and d != '*']

    # Comprueba que el correo pertenezca a un dominio admitido
    @staticmethod
    def assert_email_domain_is_allowed(email):
        """
        Se compara el dominio (lo que va despues de la ultima arroba) con la lista de dominios admitidos
        """
        allowed = AuthService.allowed_email_domains()
        if not allowed:
            return

        # rsplit y no split, ya que la parte local puede llevar arrobas entrecomilladas
        # segun el RFC, y el dominio es siempre lo que va detras de la ultima
        domain = normalize_email(email).rsplit('@', 1)[-1]

        if domain not in allowed:
            logger.warning("Rejected email outside the allowed domains: %s", email)
            raise EmailDomainNotAllowedError(email)

    # Comprueba que el nombre de usuario y el correo esten libres para un alta
    @staticmethod
    def prepare_registration(username, email):
        """
        Si el nombre de usuario lo tiene uns cuenta sin verificar, se descarta para que un registro abandonado
        no bloquee el nombre para siempre. Si lo tiene una cuenta verificada, se rechaza
        Lanza InvalidUsernameError, EmailDomainNotAllowedError, UsernameAlreadyTakenError o EmailAlreadyRegisteredError.
        """
        # Se comprueba el formato del nombre, antes que nada, porque un nombre con
        # arroba dejaria la cuenta inaccesible en cuanto se creara
        AuthService.assert_username_is_acceptable(username)

        # Se comprueba el dominio
        AuthService.assert_email_domain_is_allowed(email)

        active = Users.objects.filter(username=username, is_deleted=False)
        unverified = active.filter(is_verify=False)

        if active.exists():
            if unverified.exists():
                discarded = unverified.update(
                    is_deleted=True, deleted_at=timezone.now()
                )
                logger.info(
                    "Discarded %s unverified registration(s) for username: %s",
                    discarded, username,
                )
            else:
                logger.warning("User with same username: %s, already registered", username)
                raise UsernameAlreadyTakenError(username)

        if AuthService.email_is_taken(email):
            logger.warning("User with same email: %s, already registered", email)
            raise EmailAlreadyRegisteredError(email)

    # Arma los tokens JWT y los datos de usuario que espera la app al entrar
    @staticmethod
    def build_auth_payload(user):
        refresh = RefreshToken.for_user(user)

        # La generacion de sesiones viaja dentro del token, se pone en el refresh porque refresh.access_token
        # copia los claims del refresh, asi que con ponerlo una vez lo llevan los dos y los que emita el refresh despues
        refresh[SESSION_EPOCH_CLAIM] = user.sessions_epoch

        return {
            'refresh': str(refresh),
            'access': str(refresh.access_token),
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
                'name': user.name,
                'surname1': user.surname1,
                'surname2': user.surname2,
            },
        }

    # Valida el id_token contra Google y devuelve su payload
    @staticmethod
    def verify_google_token(id_token_str):
        try:
            return id_token.verify_oauth2_token(
                id_token_str,
                google_requests.Request(),
                config('GOOGLE_CLIENT_ID'),
            )
        except ValueError as e:
            logger.warning("Google id_token invalid: %s", str(e))
            raise InvalidGoogleTokenError(str(e))

    # Saca el correo del payload exigiendo que el proveedor lo de por verificado
    @staticmethod
    def verified_email_from_payload(payload):
        """
        En este flujo el correo es lo unico que identifica la cuenta, asi que tiene que venir verificado
        """
        email = payload.get('email')
        if not email:
            raise GoogleEmailMissingError()

        if not payload.get('email_verified', False):
            logger.warning("Rejected external login: unverified email claim for %s", email)
            raise UnverifiedEmailError(email)
        return normalize_email(email)

    # Da por verificada la cuenta a medias que reclama el dueño real del correo
    @staticmethod
    def claim_unverified_account(user):
        """
        Si la cuenta sin verificar tenia una contraseña, y se verifica con un proveedor externo, 
        se debe anular la contraseña, ya que si no se puede hacer un account pre-hijacking,
        el dueño del correo entra por Google y se queda con la cuenta, pero la contraseña que habia puesto 
        otro usuario sigue valiendo y puede entrar tambien, por lo que es obligatorio eliminar la contraseña anterior
        """
        if user.is_verify:
            return user

        user.is_verify = True

        # Se debe eliminar la contraseña si la tiene
        if user.password:
            logger.warning(
                "Password cleared for user ID: %s: the account was claimed by the owner "
                "of its email before it had ever been verified",
                user.id,
            )
            user.set_password(None)

        user.save()
        return user

    # Localiza la cuenta asociada al correo que devuelve Google
    @staticmethod
    def find_google_user(payload):
        email = AuthService.verified_email_from_payload(payload)

        try:
            user = Users.objects.get(email=email, is_deleted=False)
        except Users.DoesNotExist:
            logger.warning("Google login: user not found with email:%s", email)
            raise UserNotFoundError(email)

        AuthService.claim_unverified_account(user)

        logger.info("Google login successful: %s", email)
        return user

    # Da de alta una cuenta a partir del payload de Google
    @staticmethod
    def register_google_user(payload, username, user_type_code, surname2=None):
        """
        La cuenta nace ya verificada, ya que Google es quien acredita el correo, asi que
        no tiene sentido volver a pedir un codigo. Y sin contraseña, porque solo se entra por Google
        """
        # El alta con Google tampoco pasa por prepare_registration, asi que el
        # formato del nombre hay que exigirlo tambien aqui: el nombre lo escribe
        # el usuario en el formulario, Google solo pone el correo
        AuthService.assert_username_is_acceptable(username)

        email = AuthService.verified_email_from_payload(payload)

        # El alta con Google no pasa por prepare_registration, asi que la regla
        # del dominio hay que exigirla tambien aqui, es la otra puerta de entrada
        # y el correo lo pone el proveedor, no el formulario
        AuthService.assert_email_domain_is_allowed(email)

        if AuthService.email_is_taken(email):
            raise EmailAlreadyRegisteredError(email)

        if AuthService.username_is_taken(username):
            raise UsernameAlreadyTakenError(username)

        try:
            user_type = UserType.objects.get(code=user_type_code, is_deleted=False)
        except UserType.DoesNotExist:
            raise InvalidUserTypeError(user_type_code)

        given_name = payload.get('given_name', '')
        family_name = payload.get('family_name', given_name)

        user = Users(
            username=username,
            email=email,
            name=given_name,
            surname1=family_name,
            surname2=surname2,
            user_type=user_type,
            is_verify=True,
            has_2FA=False,
        )
        # Como se ha registrado con Google, no se necesita contraseña
        user.set_password(None)
        user.save()

        logger.info("Google registration successful: %s", email)
        return user
