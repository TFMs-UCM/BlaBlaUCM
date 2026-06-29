from decouple import config
from typing import List, Optional
from pathlib import Path

from django.core.mail import EmailMultiAlternatives
from typing import List, Optional
from pathlib import Path

class Email:
    """
    Servicio para el envio de emails
    """
    
    def __init__(self):
        self.sender = config('EMAIL_HOST_USER')

    def send_email(self, to: List[str] | str, subject: str, html: str, cc: Optional[List[str]] = None, bcc: Optional[List[str]] = None):
        """
        Funcion para enviar un email a una lista de destinatarios
        Args:
            to (List[str] | str): Lista de destinatarios 
            subject (str): Asunto del email
            html (str): Cuerpo del email en formato HTML
            cc (Optional[List[str]], optional): Lista de destinatarios en copia
            bcc (Optional[List[str]], optional): Lista de destinatarios en copia oculta
        Raises:
            RuntimeError: Si ocurre un error al enviar el email
        Returns:
            status (dict): Estado del envío del email
        """
        try:
            to_list = to if isinstance(to, list) else [to]
            email = EmailMultiAlternatives(
                subject=subject,
                body=html,
                from_email=self.sender,
                to=to_list,
                cc=cc,
                bcc=bcc,
            )

            email.attach_alternative(html, "text/html")
            email.send()

            return {"status": "sent"}

        except Exception as e:
            raise RuntimeError(f"Error enviando email: {e}")

    def send_verification_email(self, to: str, token: str):
        """Funcion para enviar un email de verificacion al usuario con un codigo de verificacion

        Args:
            to (str): Email del destinatario
            token (str): Codigo de verificación

        Raises:
            RuntimeError: Si ocurre un error al enviar el email

        Returns:
            status (dict): Estado del envío del email
        """
        # Obtener la ruta de la plantilla HTML para el email de verificacion
        root_dir = Path(__file__).resolve().parents[2]
        path = root_dir / "templates" / "verification_email.html"

        try:
            with open(path, "r", encoding="utf-8") as f:
                html = f.read()

            html = html.replace("{TOKEN}", token)

            return self.send_email(
                to=to,
                subject="Verificación de BlaBlaUCM",
                html=html
            )

        except Exception as e:
            raise RuntimeError(f"Error enviando email: {e}")